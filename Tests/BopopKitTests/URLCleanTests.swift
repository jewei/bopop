import Testing
@testable import BopopKit

@Test func urlCleanerRemovesUtmBundle() {
    let cleaned = URLCleaner.clean(
        "https://example.com/page?utm_source=a&utm_medium=b&utm_campaign=c")
    #expect(cleaned?.cleaned == "https://example.com/page")
    #expect(cleaned?.removedCount == 3)
}

@Test func urlCleanerRemovesFbclid() {
    let cleaned = URLCleaner.clean("https://example.com/?fbclid=abc123")
    #expect(cleaned?.cleaned == "https://example.com/")
    #expect(cleaned?.removedCount == 1)
}

@Test func urlCleanerStripsAmazonRefSegmentAndTag() {
    let cleaned = URLCleaner.clean(
        "https://www.amazon.com/dp/B0X/ref=sr_1_1?tag=x&keywords=y")
    #expect(cleaned?.cleaned == "https://www.amazon.com/dp/B0X?keywords=y")
    #expect(cleaned?.removedCount == 2)
}

@Test func urlCleanerKeepsTagOnFakeAmazonHost() {
    let cleaned = URLCleaner.clean("https://amazon.evil.com/dp/B0X?tag=x")
    #expect(cleaned?.cleaned == "https://amazon.evil.com/dp/B0X?tag=x")
    #expect(cleaned?.removedCount == 0)
}

@Test func urlCleanerStripsAmazonTagOnRealCcTLD() {
    let cleaned = URLCleaner.clean("https://www.amazon.co.uk/dp/B0X?tag=x")
    #expect(cleaned?.cleaned == "https://www.amazon.co.uk/dp/B0X")
    #expect(cleaned?.removedCount == 1)
}

@Test func urlCleanerRemovesYouTubeSiKeepsV() {
    let cleaned = URLCleaner.clean("https://www.youtube.com/watch?v=abc&si=xyz")
    #expect(cleaned?.cleaned == "https://www.youtube.com/watch?v=abc")
    #expect(cleaned?.removedCount == 1)
}

@Test func urlCleanerRemovesSpotifySi() {
    let cleaned = URLCleaner.clean("https://open.spotify.com/track/abc?si=xyz")
    #expect(cleaned?.cleaned == "https://open.spotify.com/track/abc")
    #expect(cleaned?.removedCount == 1)
}

@Test func urlCleanerKeepsSiOnNonYouTubeHost() {
    let cleaned = URLCleaner.clean("https://example.com/page?si=xyz")
    #expect(cleaned?.cleaned == "https://example.com/page?si=xyz")
    #expect(cleaned?.removedCount == 0)
}

@Test func urlCleanerAlreadyCleanURLReturnsZeroRemoved() {
    let cleaned = URLCleaner.clean("https://example.com/page?keep=1")
    #expect(cleaned?.original == "https://example.com/page?keep=1")
    #expect(cleaned?.cleaned == "https://example.com/page?keep=1")
    #expect(cleaned?.removedCount == 0)
}

@Test func urlCleanerRejectsNonURLText() {
    #expect(URLCleaner.clean("not a url") == nil)
    #expect(URLCleaner.clean("hello world") == nil)
}

@Test func urlCleanerRejectsNonHTTPScheme() {
    #expect(URLCleaner.clean("ftp://example.com/file") == nil)
}

@Test func urlCleanerRejectsURLWithoutHost() {
    #expect(URLCleaner.clean("mailto:foo@bar.com") == nil)
}

@Test func urlCleanerPreservesSurvivorOrder() {
    let cleaned = URLCleaner.clean(
        "https://example.com/page?a=1&utm_source=x&b=2&fbclid=y&c=3")
    #expect(cleaned?.cleaned == "https://example.com/page?a=1&b=2&c=3")
    #expect(cleaned?.removedCount == 2)
}

@Test func urlCleanerPreservesFragment() {
    let cleaned = URLCleaner.clean(
        "https://example.com/page?utm_source=a#section-2")
    #expect(cleaned?.cleaned == "https://example.com/page#section-2")
    #expect(cleaned?.removedCount == 1)
}

@Test func urlCleanerRemovesOtherGlobalTrackers() {
    let cleaned = URLCleaner.clean(
        "https://example.com/?gclid=1&mc_eid=2&igshid=3&_hsenc=4&spm=5")
    #expect(cleaned?.cleaned == "https://example.com/")
    #expect(cleaned?.removedCount == 5)
}

@MainActor
@Test func urlCleanProviderReturnsHeroResultForTrackedURL() async throws {
    let provider = URLCleanProvider()
    let query = ParsedQuery(
        mode: .general, term: "https://example.com/page?utm_source=a&utm_medium=b")

    let results = try await provider.results(for: query)

    #expect(results.count == 1)
    let result = try #require(results.first)
    #expect(result.title == "https://example.com/page")
    #expect(result.action == .openURL("https://example.com/page"))
    #expect(result.secondaryActions == [.copyText("https://example.com/page")])
    #expect(result.keywords == [query.term])
    #expect(result.icon == .symbol("link"))

    let hero = try #require(result.hero)
    #expect(hero.left == "https://example.com/page?utm_source=a&utm_medium=b")
    #expect(hero.leftBadge == "Original")
    #expect(hero.right == "https://example.com/page")
    #expect(hero.rightBadge == "2 trackers removed")

    let ranked = Ranker.rank(
        results,
        query: query.term,
        frecencyFor: { _ in 0 },
        providerWeights: Ranker.defaultWeights
    )
    #expect(ranked.map(\.id) == results.map(\.id))
}

@MainActor
@Test func urlCleanProviderReturnsSingularTrackerBadge() async throws {
    let results = try await URLCleanProvider().results(
        for: ParsedQuery(mode: .general, term: "https://example.com/?fbclid=abc123"))

    #expect(results.first?.hero?.rightBadge == "1 tracker removed")
}

@MainActor
@Test func urlCleanProviderReturnsEmptyForAlreadyCleanURL() async throws {
    let results = try await URLCleanProvider().results(
        for: ParsedQuery(mode: .general, term: "https://example.com/page?keep=1"))

    #expect(results.isEmpty)
}

@MainActor
@Test func urlCleanProviderReturnsEmptyForNonURL() async throws {
    let results = try await URLCleanProvider().results(
        for: ParsedQuery(mode: .general, term: "hello world"))

    #expect(results.isEmpty)
}

@MainActor
@Test func urlCleanProviderIgnoresOtherModes() async throws {
    let results = try await URLCleanProvider().results(
        for: ParsedQuery(mode: .fileSearch, term: "https://example.com/?fbclid=abc123"))

    #expect(results.isEmpty)
}

@Test func urlCleanerTruncatesLongURLsInHero() {
    let longPath = String(repeating: "a", count: 100)
    let cleaned = URLCleaner.clean("https://example.com/\(longPath)?utm_source=x")
    #expect(cleaned?.removedCount == 1)
    // Cleaned value itself is untruncated; provider does the truncation for hero display.
    #expect(cleaned?.cleaned == "https://example.com/\(longPath)")
}

@Test func urlCleanerStripsBareRefGlobally() throws {
    let cleaned = try #require(URLCleaner.clean(
        "https://www.raycast.com/thomas/raycast?ref=product_sidebar"))
    #expect(cleaned.cleaned == "https://www.raycast.com/thomas/raycast")
    #expect(cleaned.removedCount == 1)
}
