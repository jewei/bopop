import Foundation
import Testing
@testable import BopopKit

private func calcHero(answer: String) -> SearchResult {
    SearchResult(
        id: "calc", providerID: .calculator, title: "= \(answer)",
        keywords: ["2*(3+4)^2"], action: .copyText(answer),
        secondaryActions: [.copyText(answer)],
        hero: HeroContent(left: "2*(3+4)^2", right: "98"), sortHint: 0)
}

@Test func tabAutocompletesOnlyTheCalculatorHero() {
    #expect(TabKeyPolicy.action(hero: calcHero(answer: "98")) == .autocomplete("98"))
    #expect(TabKeyPolicy.action(hero: nil) == .cycleTab)

    let currencyHero = SearchResult(
        id: "fx", providerID: .currency, title: "123 MYR",
        action: .copyText("28.71"),
        hero: HeroContent(left: "123 MYR", right: "28.71 USD"), sortHint: 0)
    #expect(TabKeyPolicy.action(hero: currencyHero) == .cycleTab)
}

@Test func autocompletedAnswerIsReparseable() throws {
    // The plain (ungrouped) answer must feed straight back into the parser.
    let value = try ExpressionParser.evaluate("2*(3+4)^2")
    let answer = CalculatorFormatter.string(from: value)
    #expect(TabKeyPolicy.action(hero: calcHero(answer: answer)) == .autocomplete("98"))
    #expect(try ExpressionParser.evaluate("\(answer)+2") == 100)
}
