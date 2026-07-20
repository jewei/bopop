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
    private static let emptyTermResultLimit = 24

    public let id: ProviderID = .emoji

    private let catalog: EmojiCatalog
    private let frecencyFor: @Sendable (String) -> Double

    public init(catalog: EmojiCatalog, frecencyFor: @escaping @Sendable (String) -> Double) {
        self.catalog = catalog
        self.frecencyFor = frecencyFor
    }

    public func results(for query: ParsedQuery) async throws -> [SearchResult] {
        guard query.mode == .emoji else {
            return []
        }

        let indexedEntries = Array(catalog.entries.enumerated())
        let term = query.term.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !term.isEmpty else {
            let topByFrecency = indexedEntries.sorted { lhs, rhs in
                let lhsScore = frecencyFor(lhs.element.char)
                let rhsScore = frecencyFor(rhs.element.char)
                if lhsScore != rhsScore {
                    return lhsScore > rhsScore
                }
                return lhs.offset < rhs.offset
            }
            return topByFrecency.prefix(Self.emptyTermResultLimit).map {
                makeResult($0.element, catalogIndex: $0.offset)
            }
        }

        return indexedEntries.map { makeResult($0.element, catalogIndex: $0.offset) }
    }

    private func makeResult(_ entry: EmojiEntry, catalogIndex: Int) -> SearchResult {
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
