import Foundation

public struct EmojiEntry: Codable, Equatable, Sendable {
    public let char: String
    public let name: String
    public let keywords: [String]

    public init(char: String, name: String, keywords: [String]) {
        self.char = char
        self.name = name
        self.keywords = keywords
    }
}

@MainActor
public final class EmojiCatalog {
    private var cached: [EmojiEntry]?

    public init() {}

    /// Synchronous fallback: decodes on first touch if nothing warmed the
    /// catalog first.
    public var entries: [EmojiEntry] {
        if let cached {
            return cached
        }
        let decoded = Self.loadEntries()
        cached = decoded
        return decoded
    }

    /// Decodes the 174 KB catalog off the main actor and caches it. Reading
    /// `entries` cold ran that decode ON the main actor — the first keystroke
    /// in emoji mode paid for parsing ~1,900 entries before drawing anything.
    /// `AppDelegate` warms this at launch; `EmojiProvider` awaits it, so a
    /// query that arrives mid-decode joins the same work instead of racing it.
    @discardableResult
    public func load() async -> [EmojiEntry] {
        if let cached {
            return cached
        }
        // `Bundle.module` is main-actor isolated, so resolve the URL here and
        // send only that across — the decode is the expensive half anyway.
        let url = Self.resourceURL()
        let decoded = await Task.detached(priority: .utility) {
            Self.decodeEntries(at: url)
        }.value
        if cached == nil {
            cached = decoded
        }
        return cached ?? decoded
    }

    private static func loadEntries() -> [EmojiEntry] {
        decodeEntries(at: resourceURL())
    }

    /// Distributed apps copy the catalog into the conventional app Resources
    /// directory. SwiftPM tests/build products retain their generated module
    /// bundle, so use it only as a development fallback.
    private static func resourceURL() -> URL? {
        Bundle.main.url(forResource: "emoji", withExtension: "json")
            ?? Bundle.module.url(forResource: "emoji", withExtension: "json")
    }

    private nonisolated static func decodeEntries(at url: URL?) -> [EmojiEntry] {
        guard let url,
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

    public func results(for query: ParsedQuery) async throws -> [SearchResult] {
        guard query.mode == .emoji else {
            return []
        }

        // Awaits the shared off-main decode rather than forcing it on the
        // main actor (see EmojiCatalog.load).
        let catalogEntries = await catalog.load()
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
        let foldedTerm = Ranker.foldedQuery(term)
        let matching = indexedEntries.filter { indexed in
            matchesTier(foldedTerm: foldedTerm, entry: indexed.element)
        }
        return matching.map { makeResult($0.element, catalogIndex: $0.offset) }
    }

    private func matchesTier(foldedTerm: String, entry: EmojiEntry) -> Bool {
        ([entry.name] + entry.keywords).contains {
            Ranker.tier(foldedQuery: foldedTerm, candidate: $0) != .none
        }
    }

    private func makeResult(_ entry: EmojiEntry, catalogIndex: Int) -> SearchResult {
        SearchResult(
            id: entry.char,
            providerID: .emoji,
            title: "\(entry.char)  \(entry.name)",
            icon: .none,
            keywords: [entry.name] + entry.keywords,
            badge: "Emoji",
            action: .copyText(entry.char),
            sortHint: catalogIndex
        )
    }
}
