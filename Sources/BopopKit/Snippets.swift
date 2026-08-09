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

/// Snippets are authored data — the user typed them and nothing can regenerate
/// them — so this store is durable-first, unlike the regenerable caches
/// elsewhere. Every mutation reaches disk BEFORE it is published, and a failure
/// is reported rather than swallowed. Compare `ClipboardStore`, where losing a
/// capture to a failed write costs the user a clip they can copy again.
public final class SnippetStore {
    public enum StoreError: Error, Equatable {
        /// The file existed but could not be read, so it was quarantined. The
        /// user's snippets are in the `.corrupt` copy; writing a fresh file
        /// over the top would hide that copy behind a name they never see.
        case storageUnavailable
        case writeFailed(String)
    }

    public private(set) var snippets: [Snippet]
    /// False once a load has quarantined the file. Mutations refuse until the
    /// user resolves it, which Settings surfaces.
    public private(set) var isAvailable: Bool

    private static let version = 1
    private let storage: Storage

    public init(storage: Storage) {
        self.storage = storage
        switch storage.loadElementsOutcome(
            Snippet.self,
            expectedVersion: Self.version,
            from: storage.snippetsFileURL
        ) {
        case .absent:
            snippets = []
            isAvailable = true
        case .loaded(let loaded):
            snippets = loaded
            isAvailable = true
        case .unreadable:
            snippets = []
            isAvailable = false
        }
        sort()
    }

    public func add(_ snippet: Snippet) throws {
        var updated = snippets
        updated.append(snippet)
        try commit(Self.sorted(updated))
    }

    public func update(_ snippet: Snippet) throws {
        guard let index = snippets.firstIndex(where: { $0.id == snippet.id }) else {
            return
        }
        var updated = snippets
        updated[index] = snippet
        try commit(Self.sorted(updated))
    }

    public func remove(id: UUID) throws {
        var updated = snippets
        updated.removeAll { $0.id == id }
        try commit(updated)
    }

    /// Write first, publish second. The reverse order leaves the in-memory list
    /// and the file disagreeing until the next launch silently resolves it in
    /// the file's favour.
    private func commit(_ updated: [Snippet]) throws {
        guard isAvailable else {
            throw StoreError.storageUnavailable
        }
        do {
            try storage.save(updated, version: Self.version, to: storage.snippetsFileURL)
        } catch {
            throw StoreError.writeFailed(error.localizedDescription)
        }
        snippets = updated
    }

    private func sort() {
        snippets = Self.sorted(snippets)
    }

    private static func sorted(_ snippets: [Snippet]) -> [Snippet] {
        snippets.sorted {
            $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
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
                sortHint: index
            )
        }
    }
}
