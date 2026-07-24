import Foundation

public nonisolated enum ClipboardCapturePolicy {
    private static let concealedType = "org.nspasteboard.ConcealedType"
    private static let transientType = "org.nspasteboard.TransientType"

    public static func shouldCapture(
        types: [String],
        frontmostBundleID: String?,
        denied: Set<String>
    ) -> Bool {
        guard !types.contains(concealedType),
              !types.contains(transientType) else {
            return false
        }
        guard let frontmostBundleID else {
            return true
        }
        return !denied.contains(frontmostBundleID)
    }

    /// A pasteboard change carrying zero types is a deliberate upstream clear —
    /// real copies always declare types (text, images, and files included).
    public static func isUpstreamClear(types: [String]) -> Bool {
        types.isEmpty
    }
}

public struct ClipboardEntry: Codable, Equatable, Sendable {
    public let text: String
    public let capturedAt: Date
    /// `nil` = unpinned. Non-nil is both the pin flag and pin-recency key.
    public let pinnedAt: Date?

    public init(text: String, capturedAt: Date, pinnedAt: Date? = nil) {
        self.text = text
        self.capturedAt = capturedAt
        self.pinnedAt = pinnedAt
    }
}

public final class ClipboardStore {
    public private(set) var entries: [ClipboardEntry]

    private static let version = 1
    private static let maximumTextSize = 100_000

    private let storage: Storage
    private let now: () -> Date
    private var limit: Int

    public init(
        storage: Storage,
        limit: Int = 100,
        now: @escaping () -> Date = Date.init
    ) {
        self.storage = storage
        self.limit = max(1, limit)
        self.now = now
        let persistedEntries = storage.load(
            [ClipboardEntry].self,
            expectedVersion: Self.version,
            from: storage.clipboardFileURL
        ) ?? []
        entries = Self.loadEntries(persistedEntries, limit: self.limit)
    }

    public func add(_ text: String) {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return
        }
        guard text.utf8.count <= Self.maximumTextSize else {
            return
        }
        if let newest = entries.max(by: { $0.capturedAt < $1.capturedAt }),
           newest.text == text {
            return
        }

        let entry = ClipboardEntry(text: text, capturedAt: now())
        let pinCount = entries.prefix(while: { $0.pinnedAt != nil }).count
        entries.insert(entry, at: pinCount)
        trimToLimit()
        persist()
    }

    public func pin(capturedAt: Date) {
        guard let index = entries.firstIndex(where: { $0.capturedAt == capturedAt }) else {
            return
        }
        guard entries[index].pinnedAt == nil else {
            return
        }
        let existing = entries[index]
        entries[index] = ClipboardEntry(
            text: existing.text,
            capturedAt: existing.capturedAt,
            pinnedAt: now()
        )
        sortEntries()
        persist()
    }

    public func unpin(capturedAt: Date) {
        guard let index = entries.firstIndex(where: { $0.capturedAt == capturedAt }) else {
            return
        }
        guard entries[index].pinnedAt != nil else {
            return
        }
        let existing = entries[index]
        entries[index] = ClipboardEntry(
            text: existing.text,
            capturedAt: existing.capturedAt,
            pinnedAt: nil
        )
        sortEntries()
        persist()
    }

    public func setLimit(_ newLimit: Int) {
        limit = max(1, newLimit)
        trimToLimit()
        persist()
    }

    public func clear() {
        entries.removeAll { $0.pinnedAt == nil }
        persist()
    }

    /// Upstream sensitive-clear scrub: when something wipes the pasteboard with
    /// a bare clearContents (zero types — Apple Passwords does this ~90 s after
    /// a copy), drop the most recent capture so the secret doesn't outlive the
    /// clipboard here.
    public func forgetNewest(ifCapturedWithin window: TimeInterval) {
        let cutoff = now()
        guard let index = entries.indices
            .filter({ cutoff.timeIntervalSince(entries[$0].capturedAt) <= window })
            .max(by: { entries[$0].capturedAt < entries[$1].capturedAt })
        else {
            return
        }
        entries.remove(at: index)
        persist()
    }

    /// Keep every pin, then unpinned up to `limit`, then restore display order.
    private static func loadEntries(_ persisted: [ClipboardEntry], limit: Int) -> [ClipboardEntry] {
        let pinned = persisted.filter { $0.pinnedAt != nil }
        let unpinned = persisted.filter { $0.pinnedAt == nil }.prefix(limit)
        var combined = Array(pinned) + Array(unpinned)
        combined.sort(by: entrySort)
        return combined
    }

    private func trimToLimit() {
        var unpinnedCount = entries.filter { $0.pinnedAt == nil }.count
        while unpinnedCount > limit {
            guard let index = entries.lastIndex(where: { $0.pinnedAt == nil }) else {
                break
            }
            entries.remove(at: index)
            unpinnedCount -= 1
        }
    }

    private func sortEntries() {
        entries.sort(by: Self.entrySort)
    }

    private static func entrySort(_ lhs: ClipboardEntry, _ rhs: ClipboardEntry) -> Bool {
        switch (lhs.pinnedAt, rhs.pinnedAt) {
        case let (l?, r?):
            return l > r
        case (_?, nil):
            return true
        case (nil, _?):
            return false
        case (nil, nil):
            return lhs.capturedAt > rhs.capturedAt
        }
    }

    private func persist() {
        try? storage.save(
            entries,
            version: Self.version,
            to: storage.clipboardFileURL
        )
    }
}

public final class ClipboardProvider: ResultProvider {
    public let id: ProviderID = .clipboard

    private let store: ClipboardStore
    // Once this provider runs off the main actor, two overlapping generations
    // could format on this shared instance from different threads at once —
    // RelativeDateTimeFormatter is not thread-safe, so guard it with a lock
    // rather than constructing one per row (formatter construction is
    // expensive enough to matter here, same trade-off as Currency's).
    private let relativeDateFormatter: FormatterBox<RelativeDateTimeFormatter>

    public init(store: ClipboardStore) {
        self.store = store
        let formatter = RelativeDateTimeFormatter()
        formatter.dateTimeStyle = .named
        relativeDateFormatter = FormatterBox(formatter)
    }

    public nonisolated func results(for query: ParsedQuery) async throws -> [SearchResult] {
        guard query.mode == .clipboard else {
            return []
        }
        // ClipboardStore is MainActor-isolated and mutable — snapshot its
        // array rather than reading it from this off-main-actor body.
        let entries = await MainActor.run { store.entries }
        guard !entries.isEmpty else {
            return []
        }

        var results = entries.enumerated().map { index, entry in
            let pinAction: ResultAction = entry.pinnedAt == nil
                ? .pinClipboard(entry.capturedAt)
                : .unpinClipboard(entry.capturedAt)
            return SearchResult(
                id: "clip:\(entry.capturedAt.timeIntervalSince1970)",
                providerID: .clipboard,
                title: DisplayTruncation.firstLine(entry.text, limit: 60),
                subtitle: relativeDateFormatter.withLock { formatter in
                    formatter.localizedString(for: entry.capturedAt, relativeTo: Date())
                },
                icon: .symbol(entry.pinnedAt == nil ? "doc.on.clipboard" : "pin.fill"),
                // Cap searchable text so Ranker never folds 100 KB per keystroke.
                keywords: [String(entry.text.prefix(1_000))],
                badge: "Clipboard",
                action: .copyText(entry.text),
                secondaryActions: [pinAction],
                sortHint: index
            )
        }
        results.append(
            SearchResult(
                id: "clip:clear",
                providerID: .clipboard,
                title: "Clear Clipboard History",
                icon: .symbol("trash"),
                keywords: ["clear", "delete"],
                badge: "Clipboard",
                action: .clearClipboardHistory,
                secondaryActions: [],
                sortHint: entries.count
            )
        )
        return results
    }
}
