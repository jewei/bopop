import Foundation

/// Shared with CustomWebSearch.url(for:) — both encode a free-typed query
/// into a URL the same conservative way.
internal nonisolated enum QueryEncoding {
    static let allowed: CharacterSet = {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "&+?=#")
        return allowed
    }()
}

public nonisolated enum SearchEngine: String, CaseIterable, Sendable {
    case google
    case duckDuckGo
    case bing
    case brave
    case youTube
    case gitHub

    public var displayName: String {
        switch self {
        case .google: return "Google"
        case .duckDuckGo: return "DuckDuckGo"
        case .bing: return "Bing"
        case .brave: return "Brave"
        case .youTube: return "YouTube"
        case .gitHub: return "GitHub"
        }
    }

    public func searchURL(for term: String) -> URL? {
        guard let encodedTerm = term.addingPercentEncoding(withAllowedCharacters: QueryEncoding.allowed) else {
            return nil
        }

        switch self {
        case .google:
            return URL(string: "https://www.google.com/search?q=\(encodedTerm)")
        case .duckDuckGo:
            return URL(string: "https://duckduckgo.com/?q=\(encodedTerm)")
        case .bing:
            return URL(string: "https://www.bing.com/search?q=\(encodedTerm)")
        case .brave:
            return URL(string: "https://search.brave.com/search?q=\(encodedTerm)")
        case .youTube:
            return URL(string: "https://www.youtube.com/results?search_query=\(encodedTerm)")
        case .gitHub:
            return URL(string: "https://github.com/search?q=\(encodedTerm)")
        }
    }
}

public final class WebSearchProvider: ResultProvider {
    public let id: ProviderID = .webSearch

    private let engine: @Sendable () async -> SearchEngine

    public init(engine: @escaping @Sendable () async -> SearchEngine) {
        self.engine = engine
    }

    public nonisolated func results(for query: ParsedQuery) async throws -> [SearchResult] {
        guard query.mode == .general else {
            return []
        }

        let term = query.term.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty else {
            return []
        }

        let selectedEngine = await engine()
        guard let url = selectedEngine.searchURL(for: term) else {
            return []
        }

        return [
            SearchResult(
                id: "websearch",
                providerID: .webSearch,
                title: "Search \(selectedEngine.displayName) for \"\(term)\"",
                icon: .symbol("magnifyingglass"),
                keywords: [query.term],
                badge: "Web",
                action: .openURL(url.absoluteString),
                sortHint: 0
            )
        ]
    }
}
