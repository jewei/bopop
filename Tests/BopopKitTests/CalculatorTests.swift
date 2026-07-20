import Testing
@testable import BopopKit

@Test(arguments: [
    (98.0, "98"),
    (0.125, "0.125"),
    (1.0 / 3.0, "0.3333333333"),
    (-9.0, "-9"),
    (1e15, "1000000000000000")
])
func calculatorFormatterFormats(value: Double, expected: String) {
    #expect(CalculatorFormatter.string(from: value) == expected)
}

@Test(arguments: [
    ("2015", false),
    ("2+2", true),
    ("=2015", true),
    ("saf", false),
    ("pi*2", true),
    ("pie", false),
    ("2+2 extra", false),
    ("(1+2)/3", true)
])
func calculatorCandidateDetection(term: String, expected: Bool) {
    #expect(CalculatorProvider.isCandidate(term) == expected)
}

@MainActor
@Test
func calculatorProviderReturnsCopyResult() async throws {
    let provider = CalculatorProvider()
    let query = ParsedQuery(mode: .general, term: "2*(3+4)^2")

    let results = try await provider.results(for: query)

    #expect(results.count == 1)
    #expect(results.first?.title == "= 98")
    #expect(results.first?.action == .copyText("98"))
    // No secondary copy action: the primary action already is `.copyText`,
    // and ActionRunner.performCopy falls back to the primary action when
    // secondaryActions has no copyText entry of its own.
    #expect(results.first?.secondaryActions == [])
    #expect(results.first?.hero?.autocompleteText == "98")
    #expect(results.first?.keywords == [query.term])

    let ranked = Ranker.rank(
        results,
        query: query.term,
        frecencyFor: { _ in 0 },
        providerWeights: Ranker.defaultWeights
    )
    #expect(ranked.map(\.id) == ["calc"])
}

@MainActor
@Test
func calculatorProviderIgnoresNoncandidateTerm() async throws {
    let results = try await CalculatorProvider().results(
        for: ParsedQuery(mode: .general, term: "2015")
    )

    #expect(results.isEmpty)
}

@MainActor
@Test
func calculatorProviderIgnoresOtherModes() async throws {
    let results = try await CalculatorProvider().results(
        for: ParsedQuery(mode: .fileSearch, term: "2+2")
    )

    #expect(results.isEmpty)
}
