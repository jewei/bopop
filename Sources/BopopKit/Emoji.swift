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
    private let frecencyFor: BatchFrecencyLookup

    public init(catalog: EmojiCatalog, frecencyFor: @escaping BatchFrecencyLookup) {
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
            // Scores for the whole catalog are snapshotted in a single
            // MainActor hop (see BatchFrecencyLookup) instead of one hop
            // per entry.
            let scores = await frecencyFor(indexedEntries.map { $0.element.char })
            let scored = indexedEntries.map { indexed in
                (offset: indexed.offset, element: indexed.element, score: scores[indexed.element.char] ?? 0)
            }
            let byFrecency = scored.sorted { lhs, rhs in
                if lhs.score != rhs.score {
                    return lhs.score > rhs.score
                }
                return lhs.offset < rhs.offset
            }
            return byFrecency.map { makeResult($0.element, catalogIndex: $0.offset) }
        }

        // Pre-filter to entries Ranker would keep anyway (tier != .none
        // against name+keywords) before building a SearchResult for each —
        // building ~1900 unranked SearchResults per keystroke just to have
        // Ranker discard most of them was the hot-path cost here.
        let matching = indexedEntries.filter { indexed in
            matchesTier(term: term, entry: indexed.element)
        }
        return matching.map { makeResult($0.element, catalogIndex: $0.offset) }
    }

    private nonisolated func matchesTier(term: String, entry: EmojiEntry) -> Bool {
        ([entry.name] + entry.keywords).contains { Ranker.tier(query: term, candidate: $0) != .none }
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
