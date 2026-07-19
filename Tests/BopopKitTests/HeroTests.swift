import Testing
@testable import BopopKit

@Test func heroSplitTakesTopResultWithHero() {
    let hero = SearchResult(id: "x", providerID: .currency, title: "t",
        action: .copyText("v"),
        hero: HeroContent(left: "123 MYR", right: "$30.03"), sortHint: 0)
    let plain = SearchResult(id: "y", providerID: .apps, title: "Safari",
        action: .openApp("s"), sortHint: 0)
    let split = HeroPresentation.split([hero, plain])
    #expect(split.hero?.id == "x")
    #expect(split.rows.map(\.id) == ["y"])
}

@Test func heroSplitPassesThroughWhenTopHasNoHero() {
    let plain = SearchResult(id: "y", providerID: .apps, title: "Safari",
        action: .openApp("s"), sortHint: 0)
    let split = HeroPresentation.split([plain])
    #expect(split.hero == nil)
    #expect(split.rows.map(\.id) == ["y"])
}

@MainActor
@Test func calculatorResultCarriesHero() async throws {
    let results = try await CalculatorProvider().results(
        for: ParsedQuery(mode: .general, term: "123*456"))
    let hero = try #require(results.first?.hero)
    #expect(hero.left == "123*456")
    #expect(hero.right == "56,088")
    #expect(hero.rightBadge == "Fifty-Six Thousand Eighty-Eight")
}

@Test func queryParserEmojiPrefix() {
    #expect(QueryParser.parse(raw: ":fire", stickyMode: .general)
        == ParsedQuery(mode: .emoji, term: "fire"))
    #expect(QueryParser.parse(raw: ":", stickyMode: .general).mode == .general)
    #expect(QueryParser.parse(raw: "t hello", stickyMode: .general)
        == ParsedQuery(mode: .translation, term: "hello"))
}

@Test func escapeExitsNewModes() {
    #expect(EscapePolicy.action(textIsEmpty: true, stickyMode: .emoji) == .exitMode)
    #expect(EscapePolicy.action(textIsEmpty: true, stickyMode: .translation) == .exitMode)
}
