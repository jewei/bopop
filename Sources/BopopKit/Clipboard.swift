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

    public init(text: String, capturedAt: Date) {
        self.text = text
        self.capturedAt = capturedAt
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
        entries = Array(persistedEntries.prefix(self.limit))
    }

    public func add(_ text: String) {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return
        }
        guard text.utf8.count <= Self.maximumTextSize else {
            return
        }
        guard text != entries.first?.text else {
            return
        }

        entries.insert(
            ClipboardEntry(text: text, capturedAt: now()),
            at: entries.startIndex
        )
        trimToLimit()
        persist()
    }

    public func setLimit(_ newLimit: Int) {
        limit = max(1, newLimit)
        trimToLimit()
        persist()
    }

    public func clear() {
        entries.removeAll()
        persist()
    }

    /// Upstream sensitive-clear scrub: when something wipes the pasteboard with
    /// a bare clearContents (zero types — Apple Passwords does this ~90 s after
    /// a copy), drop the most recent capture so the secret doesn't outlive the
    /// clipboard here.
    public func forgetNewest(ifCapturedWithin window: TimeInterval) {
        guard let newest = entries.first,
              now().timeIntervalSince(newest.capturedAt) <= window else {
            return
        }
        entries.removeFirst()
        persist()
    }

    private func trimToLimit() {
        if entries.count > limit {
            entries.removeLast(entries.count - limit)
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
            SearchResult(
                id: "clip:\(entry.capturedAt.timeIntervalSince1970)",
                providerID: .clipboard,
                title: title(for: entry.text),
                subtitle: relativeDateFormatter.withLock { formatter in
                    formatter.localizedString(for: entry.capturedAt, relativeTo: Date())
                },
                icon: .symbol("doc.on.clipboard"),
                // Cap searchable text so Ranker never folds 100 KB per keystroke.
                keywords: [String(entry.text.prefix(1_000))],
                action: .copyText(entry.text),
                secondaryActions: [.copyText(entry.text)],
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
                action: .clearClipboardHistory,
                secondaryActions: [],
                sortHint: entries.count
            )
        )
        return results
    }

    private nonisolated func title(for text: String) -> String {
        let firstLine = text.components(separatedBy: .newlines).first ?? ""
        let trimmed = firstLine.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > 60 else {
            return trimmed
        }
        return String(trimmed.prefix(60)) + "…"
    }
}
