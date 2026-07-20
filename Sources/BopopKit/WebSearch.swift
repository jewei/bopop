import Foundation

public nonisolated enum SearchEngine: String, CaseIterable, Sendable {
    case google
    case duckDuckGo
    case bing
    case brave

    public var displayName: String {
        switch self {
        case .google: return "Google"
        case .duckDuckGo: return "DuckDuckGo"
        case .bing: return "Bing"
        case .brave: return "Brave"
        }
    }

    public func searchURL(for term: String) -> URL? {
        guard let encodedTerm = term.addingPercentEncoding(withAllowedCharacters: Self.queryAllowed) else {
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
        }
    }

    private static let queryAllowed: CharacterSet = {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "&+?=#")
        return allowed
    }()
}

public final class WebSearchProvider: ResultProvider {
    public let id: ProviderID = .webSearch

    private let engine: @Sendable () -> SearchEngine

    public init(engine: @escaping @Sendable () -> SearchEngine) {
        self.engine = engine
    }

    public func results(for query: ParsedQuery) async throws -> [SearchResult] {
        guard query.mode == .general else {
            return []
        }

        let term = query.term.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty else {
            return []
        }

        let selectedEngine = engine()
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
