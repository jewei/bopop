import Foundation

public nonisolated struct CustomWebSearch: Codable, Equatable, Sendable, Identifiable {
    public let id: UUID
    public var name: String
    public var keyword: String
    public var urlTemplate: String

    public init(id: UUID, name: String, keyword: String, urlTemplate: String) {
        self.id = id
        self.name = name
        self.keyword = keyword
        self.urlTemplate = urlTemplate
    }

    public var isValid: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
            && !keyword.isEmpty
            && !keyword.contains(where: \.isWhitespace)
            && !Self.isReservedKeyword(keyword)
            && urlTemplate.contains("{query}")
    }

    public func url(for term: String) -> URL? {
        guard let encoded = term.addingPercentEncoding(withAllowedCharacters: QueryEncoding.allowed) else {
            return nil
        }
        return URL(string: urlTemplate.replacingOccurrences(of: "{query}", with: encoded))
    }

    /// "f"/"t" are QueryParser's sticky-mode prefixes ("f " → file search,
    /// "t " → translation) and a leading ":" is the emoji prefix — none of
    /// these keywords can ever reach CustomSearchProvider in .general mode,
    /// so a custom search saved under one would be permanently dead.
    static func isReservedKeyword(_ keyword: String) -> Bool {
        if keyword.hasPrefix(":") {
            return true
        }
        switch keyword.lowercased() {
        case "f", "t":
            return true
        default:
            return false
        }
    }

    public static func match(
        term: String,
        searches: [CustomWebSearch]
    ) -> (search: CustomWebSearch, remainder: String)? {
        let trimmed = term.trimmingCharacters(in: .whitespacesAndNewlines)
        for search in searches where !search.keyword.isEmpty {
            let prefix = search.keyword.lowercased() + " "
            guard trimmed.lowercased().hasPrefix(prefix) else { continue }
            let remainder = String(trimmed.dropFirst(prefix.count))
                .trimmingCharacters(in: .whitespaces)
            guard !remainder.isEmpty else { continue }
            return (search, remainder)
        }
        return nil
    }
}

public final class CustomSearchProvider: ResultProvider {
    public let id: ProviderID = .customSearch

    private let searches: @Sendable () -> [CustomWebSearch]

    public init(searches: @escaping @Sendable () -> [CustomWebSearch]) {
        self.searches = searches
    }

    public func results(for query: ParsedQuery) async throws -> [SearchResult] {
        guard query.mode == .general,
              let (search, remainder) = CustomWebSearch.match(term: query.term, searches: searches()),
              let url = search.url(for: remainder) else {
            return []
        }
        return [
            SearchResult(
                id: "customsearch:\(search.id.uuidString)",
                providerID: .customSearch,
                title: "Search \(search.name) for \"\(remainder)\"",
                icon: .symbol("globe"),
                // Raw term keeps this at the exact tier so it ranks by weight.
                keywords: [query.term],
                badge: "Web",
                action: .openURL(url.absoluteString),
                sortHint: 0
            )
        ]
    }
}
