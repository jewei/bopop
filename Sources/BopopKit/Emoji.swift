import Foundation

public nonisolated struct EmojiEntry: Codable, Equatable, Sendable {
    public let char: String
    public let name: String
    public let keywords: [String]

    public init(char: String, name: String, keywords: [String]) {
        self.char = char
        self.name = name
        self.keywords = keywords
    }
}

public final class EmojiCatalog {
    public private(set) lazy var entries: [EmojiEntry] = Self.loadEntries()

    public init() {}

    private static func loadEntries() -> [EmojiEntry] {
        guard let url = Bundle.module.url(forResource: "emoji", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let entries = try? JSONDecoder().decode([EmojiEntry].self, from: data)
        else {
            return []
        }
        return entries
    }
}

public final class EmojiProvider: ResultProvider {
    public let id: ProviderID = .emoji

    private let catalog: EmojiCatalog
    private let frecencyFor: @Sendable (String) async -> Double

    public init(catalog: EmojiCatalog, frecencyFor: @escaping @Sendable (String) async -> Double) {
        self.catalog = catalog
        self.frecencyFor = frecencyFor
    }

    public nonisolated func results(for query: ParsedQuery) async throws -> [SearchResult] {
        guard query.mode == .emoji else {
            return []
        }

        // EmojiCatalog's `entries` is a lazy var — force it to initialize on
        // MainActor (its home isolation) rather than racing a first access
        // from this now off-main-actor body.
        let catalogEntries = await MainActor.run { catalog.entries }
        let indexedEntries = Array(catalogEntries.enumerated())
        let term = query.term.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !term.isEmpty else {
            // Grid mode scrolls through the FULL catalog frecency-first
            // (ties broken by catalog order) rather than the old top-24
            // list cutoff — the tile grid has room to browse everything.
            var scored: [(offset: Int, element: EmojiEntry, score: Double)] = []
            for indexed in indexedEntries {
                let score = await frecencyFor(indexed.element.char)
                scored.append((indexed.offset, indexed.element, score))
            }
            let byFrecency = scored.sorted { lhs, rhs in
                if lhs.score != rhs.score {
                    return lhs.score > rhs.score
                }
                return lhs.offset < rhs.offset
            }
            return byFrecency.map { makeResult($0.element, catalogIndex: $0.offset) }
        }

        return indexedEntries.map { makeResult($0.element, catalogIndex: $0.offset) }
    }

    private nonisolated func makeResult(_ entry: EmojiEntry, catalogIndex: Int) -> SearchResult {
        SearchResult(
            id: entry.char,
            providerID: .emoji,
            title: "\(entry.char)  \(entry.name)",
            icon: .none,
            keywords: [entry.name] + entry.keywords,
            action: .copyText(entry.char),
            sortHint: catalogIndex
        )
    }
}
