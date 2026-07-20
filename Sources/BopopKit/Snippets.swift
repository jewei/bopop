import Foundation

public nonisolated struct Snippet: Codable, Equatable, Sendable, Identifiable {
    public let id: UUID
    public var name: String
    public var keyword: String?
    public var content: String

    public init(id: UUID, name: String, keyword: String?, content: String) {
        self.id = id
        self.name = name
        self.keyword = keyword
        self.content = content
    }
}

public final class SnippetStore {
    public private(set) var snippets: [Snippet]

    private static let version = 1
    private let storage: Storage

    public init(storage: Storage) {
        self.storage = storage
        snippets = storage.load(
            [Snippet].self,
            expectedVersion: Self.version,
            from: storage.snippetsFileURL
        ) ?? []
        sort()
    }

    public func add(_ snippet: Snippet) {
        snippets.append(snippet)
        sort()
        persist()
    }

    public func update(_ snippet: Snippet) {
        guard let index = snippets.firstIndex(where: { $0.id == snippet.id }) else { return }
        snippets[index] = snippet
        sort()
        persist()
    }

    public func remove(id: UUID) {
        snippets.removeAll { $0.id == id }
        persist()
    }

    private func sort() {
        snippets.sort {
            $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }

    private func persist() {
        try? storage.save(snippets, version: Self.version, to: storage.snippetsFileURL)
    }
}

public final class SnippetsProvider: ResultProvider {
    public let id: ProviderID = .snippets

    private let store: SnippetStore

    public init(store: SnippetStore) {
        self.store = store
    }

    public nonisolated func results(for query: ParsedQuery) async throws -> [SearchResult] {
        switch query.mode {
        case .general:
            guard !query.term.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return []
            }
        case .snippets:
            break
        default:
            return []
        }
        // SnippetStore is MainActor-isolated and mutable — snapshot its
        // array rather than reading it from this off-main-actor body.
        let snippets = await MainActor.run { store.snippets }
        return snippets.enumerated().map { index, snippet in
            SearchResult(
                id: "snippet:\(snippet.id.uuidString)",
                providerID: .snippets,
                title: snippet.name,
                subtitle: DisplayTruncation.firstLine(snippet.content, limit: 60),
                icon: .symbol("text.quote"),
                keywords: [snippet.name] + (snippet.keyword.map { [$0] } ?? []),
                badge: "Snippet",
                action: .copyText(snippet.content),
                secondaryActions: [.copyText(snippet.content)],
                sortHint: index
            )
        }
    }
}
