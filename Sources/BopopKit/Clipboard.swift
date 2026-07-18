import Foundation

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
    private let relativeDateFormatter: RelativeDateTimeFormatter

    public init(store: ClipboardStore) {
        self.store = store
        let formatter = RelativeDateTimeFormatter()
        formatter.dateTimeStyle = .named
        relativeDateFormatter = formatter
    }

    public func results(for query: ParsedQuery) async throws -> [SearchResult] {
        guard query.mode == .clipboard else {
            return []
        }

        return store.entries.enumerated().map { index, entry in
            SearchResult(
                id: "clip:\(entry.capturedAt.timeIntervalSince1970)",
                providerID: .clipboard,
                title: title(for: entry.text),
                subtitle: relativeDateFormatter.localizedString(
                    for: entry.capturedAt,
                    relativeTo: Date()
                ),
                icon: .symbol("doc.on.clipboard"),
                // Cap searchable text so Ranker never folds 100 KB per keystroke.
                keywords: [String(entry.text.prefix(1_000))],
                action: .copyText(entry.text),
                secondaryActions: [.copyText(entry.text)],
                sortHint: index
            )
        }
    }

    private func title(for text: String) -> String {
        let firstLine = text.components(separatedBy: .newlines).first ?? ""
        let trimmed = firstLine.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > 60 else {
            return trimmed
        }
        return String(trimmed.prefix(60)) + "…"
    }
}
