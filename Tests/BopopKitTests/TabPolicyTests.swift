import Foundation
import Testing
@testable import BopopKit

private func calcHero(answer: String) -> SearchResult {
    SearchResult(
        id: "calc", providerID: .calculator, title: "= \(answer)",
        keywords: ["2*(3+4)^2"], action: .copyText(answer),
        hero: HeroContent(left: "2*(3+4)^2", right: "98", autocompleteText: answer), sortHint: 0)
}

@Test func tabAutocompletesOnlyHeroesThatSetAutocompleteText() {
    #expect(TabKeyPolicy.action(hero: calcHero(answer: "98")) == .autocomplete("98"))
    #expect(TabKeyPolicy.action(hero: nil) == .cycleTab)

    // Currency's hero sets no `autocompleteText` — it must keep cycling
    // tabs, not autocomplete, even though it's a hero with a `.copyText`
    // action (the policy no longer keys off providerID or action shape).
    let currencyHero = SearchResult(
        id: "fx", providerID: .currency, title: "123 MYR",
        action: .copyText("28.71"),
        hero: HeroContent(left: "123 MYR", right: "28.71 USD"), sortHint: 0)
    #expect(TabKeyPolicy.action(hero: currencyHero) == .cycleTab)
}

@Test func tabAutocompletesAnyProviderThatSetsAutocompleteText() {
    // Proves the generalization: a hero from a non-calculator provider that
    // opts into `autocompleteText` autocompletes too.
    let genericHero = SearchResult(
        id: "generic", providerID: .translation, title: "t",
        action: .copyText("x"),
        hero: HeroContent(left: "l", right: "r", autocompleteText: "answer"), sortHint: 0)
    #expect(TabKeyPolicy.action(hero: genericHero) == .autocomplete("answer"))
}

@Test func autocompletedAnswerIsReparseable() throws {
    // The plain (ungrouped) answer must feed straight back into the parser.
    let value = try ExpressionParser.evaluate("2*(3+4)^2")
    let answer = CalculatorFormatter.string(from: value)
    #expect(TabKeyPolicy.action(hero: calcHero(answer: answer)) == .autocomplete("98"))
    #expect(try ExpressionParser.evaluate("\(answer)+2") == 100)
}
