import Foundation

public nonisolated enum ClipboardCapturePolicy {
    /// Markers a source puts on a copy it considers secret — a password, a
    /// one-time code, an autofill value. Never recorded, whatever app set
    /// them. The two `org.nspasteboard.*` ones are the cross-app convention;
    /// `com.apple.is-sensitive` is Apple's own, set by system autofill and by
    /// browsers on password and OTP fields, and a copy carrying only that one
    /// used to be captured and written to disk like any other.
    public static let sensitiveTypes: Set<String> = [
        "org.nspasteboard.ConcealedType",
        "org.nspasteboard.TransientType",
        "com.apple.is-sensitive"
    ]

    public static func shouldCapture(
        types: [String],
        frontmostBundleID: String?,
        denied: Set<String>
    ) -> Bool {
        guard !types.contains(where: sensitiveTypes.contains) else {
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

public struct ClipboardEntry: Codable, Equatable, Sendable, Identifiable {
    /// Stable primary key for pin/unpin and `SearchResult.id`. `capturedAt`
    /// used to serve as one, but it round-trips through JSON as a Double and
    /// two clips captured in the same instant collide — pin then acted on the
    /// wrong row, or silently on none.
    public let id: UUID
    public let text: String
    public let capturedAt: Date
    /// `nil` = unpinned. Non-nil is both the pin flag and pin-recency key.
    public let pinnedAt: Date?

    public init(
        id: UUID = UUID(),
        text: String,
        capturedAt: Date,
        pinnedAt: Date? = nil
    ) {
        self.id = id
        self.text = text
        self.capturedAt = capturedAt
        self.pinnedAt = pinnedAt
    }

    /// `id` postdates the v1 file format, and bumping the version quarantines
    /// the existing file (see `Storage.load`) — so entries persisted without
    /// one get a fresh id on load rather than costing the user their history.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        text = try container.decode(String.self, forKey: .text)
        capturedAt = try container.decode(Date.self, forKey: .capturedAt)
        pinnedAt = try container.decodeIfPresent(Date.self, forKey: .pinnedAt)
    }

    fileprivate func pinned(at date: Date?) -> ClipboardEntry {
        ClipboardEntry(id: id, text: text, capturedAt: capturedAt, pinnedAt: date)
    }
}

public final class ClipboardStore {
    public private(set) var entries: [ClipboardEntry]

    private static let version = 1
    private static let maximumTextSize = 100_000
    /// Pins are exempt from `limit`, so they need a ceiling of their own —
    /// without one the store, the persisted file, and the per-keystroke work
    /// in `ClipboardProvider` all grow unbounded. Passing it demotes the
    /// oldest pin: the entry stays in history, it just stops being exempt.
    public static let maximumPinnedEntries = 50

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
        let persistedEntries = storage.loadElements(
            ClipboardEntry.self,
            expectedVersion: Self.version,
            from: storage.clipboardFileURL
        ) ?? []
        entries = persistedEntries.sorted(by: Self.entrySort)
        enforceLimits()
    }

    public func add(_ text: String) {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return
        }
        guard text.utf8.count <= Self.maximumTextSize else {
            return
        }
        // Dedup is deliberately consecutive-only: re-copying an older history
        // row promotes it as a fresh capture. Pinned text is the exception —
        // activating a pin puts its text back on the pasteboard, and
        // PasteboardWatcher reads it straight back, so without this guard
        // every pin the user actually uses grows an unpinned twin.
        if let newest = entries.max(by: { $0.capturedAt < $1.capturedAt }),
           newest.text == text {
            return
        }
        guard !entries.contains(where: { $0.pinnedAt != nil && $0.text == text }) else {
            return
        }

        let entry = ClipboardEntry(text: text, capturedAt: now())
        entries.insert(entry, at: pinnedCount)
        enforceLimits()
        persist()
    }

    public func pin(id: UUID) {
        guard let index = entries.firstIndex(where: { $0.id == id }),
              entries[index].pinnedAt == nil else {
            return
        }
        entries[index] = entries[index].pinned(at: now())
        sortEntries()
        enforceLimits()
        persist()
    }

    public func unpin(id: UUID) {
        guard let index = entries.firstIndex(where: { $0.id == id }),
              entries[index].pinnedAt != nil else {
            return
        }
        entries[index] = entries[index].pinned(at: nil)
        sortEntries()
        // The entry rejoins the unpinned pool, which can push it over `limit`
        // — every other mutation trims, and this one used to be the exception.
        enforceLimits()
        persist()
    }

    public func setLimit(_ newLimit: Int) {
        limit = max(1, newLimit)
        enforceLimits()
        persist()
    }

    /// Drops unpinned history only — a pin is the user's explicit "keep this".
    /// `ClipboardProvider` hides the Clear row entirely when nothing is left
    /// to drop, and names what it keeps when some of it is pinned, so this
    /// never reads as a full wipe that quietly wasn't.
    public func clear() {
        entries.removeAll { $0.pinnedAt == nil }
        persist()
    }

    /// Upstream sensitive-clear scrub: when something wipes the pasteboard with
    /// a bare clearContents (zero types — Apple Passwords does this ~90 s after
    /// a copy), drop every capture from that window so the secret doesn't
    /// outlive the clipboard here.
    ///
    /// Every capture, not just the newest. A password manager schedules its
    /// wipe per copy, but a second copy replaces the first on the pasteboard,
    /// so only one wipe lands — and scrubbing one entry per wipe left the
    /// earlier password in history for good. Found by manual QA: "i copied 2
    /// passwords, 1 is gone, another 1 stays."
    ///
    /// The cost is deliberate: an unrelated copy made inside the same window
    /// goes too. Losing a clipboard entry is an inconvenience, and a password
    /// left behind is not.
    ///
    /// Pinned entries are never scrubbed. This heuristic can't tell a password
    /// manager's clear from any other app's (see the comment above), so it must
    /// not be able to destroy something the user explicitly asked to keep.
    public func forgetCaptures(within window: TimeInterval) {
        // `entrySort` puts pins first and orders the unpinned tail newest-first,
        // so the unpinned run starts right after the pins.
        let cutoff = now().addingTimeInterval(-window)
        let survivors = entries.enumerated().filter { index, entry in
            index < pinnedCount || entry.capturedAt < cutoff
        }
        guard survivors.count != entries.count else {
            return
        }
        entries = survivors.map(\.element)
        persist()
    }

    /// Length of the leading pinned run — `entrySort`'s invariant is that pins
    /// form the head of `entries` and unpinned entries the tail.
    private var pinnedCount: Int {
        entries.prefix { $0.pinnedAt != nil }.count
    }

    /// The single owner of both caps, shared by every mutation and by load, so
    /// the policy can't drift between them. Excess pins demote rather than
    /// vanish; only unpinned entries are ever dropped. Requires `entries` to
    /// already satisfy `entrySort`'s invariant.
    private func enforceLimits() {
        let pinned = pinnedCount
        if pinned > Self.maximumPinnedEntries {
            for index in Self.maximumPinnedEntries..<pinned {
                entries[index] = entries[index].pinned(at: nil)
            }
            sortEntries()
        }
        let unpinnedCount = entries.count - min(pinned, Self.maximumPinnedEntries)
        if unpinnedCount > limit {
            entries.removeLast(unpinnedCount - limit)
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

    /// Deliberately synchronous. Writing the whole array on every mutation is
    /// O(n) work for an O(1) event, so this was tried as a background write —
    /// but measurement said the trade is bad: a realistic history (150 entries
    /// of a few hundred bytes) encodes and writes in ~1 ms, and even 150 × 2 KB
    /// is ~1.4 ms. Only the pathological ceiling — 150 entries all at the
    /// 100 KB `maximumTextSize`, i.e. 15 MB of clipboard text — reaches ~42 ms.
    ///
    /// Going async bought that ~1 ms and cost read-after-write: a store built
    /// straight after a mutation saw stale data, and an unclean exit could drop
    /// the newest capture or pin. Durability is worth more than a millisecond
    /// here. If a profile ever shows this mattering, the fix is an incremental
    /// store (one row per entry), not a deferred whole-file write.
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

        return PerformanceSignposts.provider.interval("Clipboard Results Build") {
            buildResults(from: entries)
        }
    }

    private nonisolated func buildResults(
        from entries: [ClipboardEntry]
    ) -> [SearchResult] {
        // No pre-filter here, unlike AppsProvider. Measured: filtering first
        // only moves the folding work out of Ranker and into this method, and
        // buys 4-5% end to end. The cost that matters is folding the 1000-char
        // searchable text once per entry per keystroke, which both paths pay.
        // See docs/performance-baseline.md.
        let now = Date()
        var results = entries.enumerated().map { index, entry in
            let pinAction: ResultAction = entry.pinnedAt == nil
                ? .pinClipboard(entry.id)
                : .unpinClipboard(entry.id)
            return SearchResult(
                id: "clip:\(entry.id.uuidString)",
                providerID: .clipboard,
                title: DisplayTruncation.firstLine(entry.text, limit: 60),
                subtitle: relativeDateFormatter.withLock { formatter in
                    formatter.localizedString(for: entry.capturedAt, relativeTo: now)
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
        // Clear drops unpinned history only, so it's hidden rather than
        // offered as a no-op once everything left is pinned, and it names what
        // it keeps when only some of it is.
        let pinnedCount = entries.count { $0.pinnedAt != nil }
        guard pinnedCount < entries.count else {
            return results
        }
        results.append(
            SearchResult(
                id: "clip:clear",
                providerID: .clipboard,
                title: "Clear Clipboard History",
                subtitle: pinnedCount == 0
                    ? nil
                    : "Keeps \(pinnedCount) pinned item\(pinnedCount == 1 ? "" : "s")",
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
