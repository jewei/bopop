import Testing
@testable import BopopKit

@Test(arguments: [
    (SearchEngine.google, "swift", "https://www.google.com/search?q=swift"),
    (SearchEngine.duckDuckGo, "swift", "https://duckduckgo.com/?q=swift"),
    (SearchEngine.bing, "swift", "https://www.bing.com/search?q=swift"),
    (SearchEngine.brave, "swift", "https://search.brave.com/search?q=swift"),
    (
        SearchEngine.google, "swift 6 concurrency",
        "https://www.google.com/search?q=swift%206%20concurrency"
    ),
    (
        SearchEngine.duckDuckGo, "swift 6 concurrency",
        "https://duckduckgo.com/?q=swift%206%20concurrency"
    ),
    (
        SearchEngine.bing, "swift 6 concurrency",
        "https://www.bing.com/search?q=swift%206%20concurrency"
    ),
    (
        SearchEngine.brave, "swift 6 concurrency",
        "https://search.brave.com/search?q=swift%206%20concurrency"
    ),
    (SearchEngine.google, "蘋果", "https://www.google.com/search?q=%E8%98%8B%E6%9E%9C"),
    (SearchEngine.google, "a&b=c#d", "https://www.google.com/search?q=a%26b%3Dc%23d")
])
func searchEngineBuildsExactURL(engine: SearchEngine, term: String, expected: String) {
    #expect(engine.searchURL(for: term)?.absoluteString == expected)
}

@Test
func searchEngineDisplayNames() {
    #expect(SearchEngine.google.displayName == "Google")
    #expect(SearchEngine.duckDuckGo.displayName == "DuckDuckGo")
    #expect(SearchEngine.bing.displayName == "Bing")
    #expect(SearchEngine.brave.displayName == "Brave")
}

@MainActor
@Test
func webSearchProviderReturnsRowForGeneralModeNonEmptyTerm() async throws {
    let provider = WebSearchProvider(engine: { .google })
    let results = try await provider.results(
        for: ParsedQuery(mode: .general, term: "apple")
    )

    #expect(results.count == 1)
    let result = try #require(results.first)
    #expect(result.id == "websearch")
    #expect(result.providerID == .webSearch)
    #expect(result.title == "Search Google for \"apple\"")
    #expect(result.icon == .symbol("magnifyingglass"))
    #expect(result.badge == "Web")
    #expect(result.keywords == ["apple"])
    #expect(result.sortHint == 0)
    guard case let .openURL(urlString) = result.action else {
        Issue.record("expected openURL action")
        return
    }
    #expect(urlString == "https://www.google.com/search?q=apple")
}

@MainActor
@Test
func webSearchProviderEmptyOrWhitespaceTermReturnsNoResults() async throws {
    let provider = WebSearchProvider(engine: { .google })
    let empty = try await provider.results(for: ParsedQuery(mode: .general, term: ""))
    let whitespace = try await provider.results(for: ParsedQuery(mode: .general, term: "   "))
    #expect(empty.isEmpty)
    #expect(whitespace.isEmpty)
}

@MainActor
@Test(arguments: [Mode.fileSearch, .clipboard, .emoji, .translation, .apps])
func webSearchProviderWrongModeReturnsNoResults(mode: Mode) async throws {
    let provider = WebSearchProvider(engine: { .google })
    let results = try await provider.results(for: ParsedQuery(mode: mode, term: "apple"))
    #expect(results.isEmpty)
}

@Test(arguments: [
    (ProviderID.apps, nil as String?, "Apps" as String?),
    (ProviderID.files, nil, "Files"),
    (ProviderID.clipboard, nil, "Clipboard"),
    (ProviderID.emoji, nil, "Emoji"),
    (ProviderID.webSearch, nil, "Web"),
    (ProviderID.calculator, nil, nil),
    (ProviderID.scripts, "Script", "Script"),
    (ProviderID.apps, "Custom", "Custom")
])
func categoryBadgeText(
    providerID: ProviderID,
    explicitBadge: String?,
    expected: String?
) {
    let result = SearchResult(
        id: "x",
        providerID: providerID,
        title: "t",
        badge: explicitBadge,
        action: .copyText("v"),
        sortHint: 0
    )
    #expect(CategoryBadge.text(for: result) == expected)
}

@Test func searchEngineYouTubeAndGitHubURLs() {
    #expect(SearchEngine.youTube.searchURL(for: "swift concurrency")?.absoluteString
        == "https://www.youtube.com/results?search_query=swift%20concurrency")
    #expect(SearchEngine.gitHub.searchURL(for: "bopop")?.absoluteString
        == "https://github.com/search?q=bopop")
}
