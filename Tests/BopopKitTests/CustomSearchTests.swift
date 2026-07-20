import Foundation
import Testing
@testable import BopopKit

private let youtube = CustomWebSearch(
    id: UUID(), name: "YouTube", keyword: "yt",
    urlTemplate: "https://www.youtube.com/results?search_query={query}")

@Test func customSearchMatchesKeywordPrefixCaseInsensitively() {
    let match = CustomWebSearch.match(term: "YT cute cats", searches: [youtube])
    #expect(match?.search.id == youtube.id)
    #expect(match?.remainder == "cute cats")
    #expect(CustomWebSearch.match(term: "yt", searches: [youtube]) == nil)   // no term
    #expect(CustomWebSearch.match(term: "yt ", searches: [youtube]) == nil)  // empty term
    #expect(CustomWebSearch.match(term: "yts x", searches: [youtube]) == nil) // not the keyword
}

@Test func customSearchBuildsPercentEncodedURL() {
    let url = youtube.url(for: "cute cats & dogs?")
    #expect(url?.absoluteString
        == "https://www.youtube.com/results?search_query=cute%20cats%20%26%20dogs%3F")
}

@Test func customSearchValidation() {
    #expect(youtube.isValid)
    #expect(!CustomWebSearch(id: UUID(), name: "X", keyword: "two words",
                             urlTemplate: "https://x.com/{query}").isValid)
    #expect(!CustomWebSearch(id: UUID(), name: "X", keyword: "x",
                             urlTemplate: "https://x.com/").isValid) // no {query}
}

@Test func customSearchCodableRoundTrip() throws {
    let data = try JSONEncoder().encode([youtube])
    let decoded = try JSONDecoder().decode([CustomWebSearch].self, from: data)
    #expect(decoded == [youtube])
}

@MainActor
@Test func customSearchProviderEmitsPinnedRow() async throws {
    let provider = CustomSearchProvider(searches: { [youtube] })
    let results = try await provider.results(for: ParsedQuery(mode: .general, term: "yt cute cats"))
    let row = try #require(results.first)
    #expect(row.title == "Search YouTube for \"cute cats\"")
    #expect(row.badge == "Web")
    #expect(row.providerID == .customSearch)
    if case .openURL(let urlString) = row.action {
        #expect(urlString.contains("cute%20cats"))
    } else { Issue.record("expected openURL") }

    let none = try await provider.results(for: ParsedQuery(mode: .general, term: "hello"))
    #expect(none.isEmpty)
    #expect(Ranker.defaultWeights[.customSearch] == 105)
}
