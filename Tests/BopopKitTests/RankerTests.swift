import Testing
@testable import BopopKit

@Test(arguments: [
    ("safari", "Safari", MatchTier.exact),
    ("saf", "Safari", MatchTier.prefix),
    ("gc", "Google Chrome", MatchTier.wordBoundary),
    ("chr", "Google Chrome", MatchTier.wordBoundary),
    ("fari", "Safari", MatchTier.substring),
    ("sfr", "Safari", MatchTier.subsequence),
    ("xyz", "Safari", MatchTier.none),
    ("cafe", "Café", MatchTier.exact)
])
func matchTiers(query: String, candidate: String, expected: MatchTier) {
    #expect(Ranker.tier(query: query, candidate: candidate) == expected)
}

@Test
func rankerUsesBestKeywordTier() {
    let result = makeResult(
        id: "app:vscode",
        title: "Visual Studio Code",
        keywords: ["Code"]
    )
    let score = Ranker.score(
        result,
        query: "code",
        frecency: 0,
        providerWeight: 0
    )

    #expect(score >= Double(MatchTier.prefix.rawValue * 1_000))
}

@Test
func tierStrictlyDominatesProviderWeightAndFrecency() {
    // A lower-tier (subsequence) match with a big provider weight and near-max
    // frecency must never outrank a higher-tier (substring) match that has
    // neither — tier is supposed to be the dominant signal.
    let subsequenceResult = makeResult(id: "subsequence", providerID: .urlClean, title: "a1b2c3")
    let substringResult = makeResult(id: "substring", providerID: .files, title: "xabcx")

    let ranked = Ranker.rank(
        [subsequenceResult, substringResult],
        query: "abc",
        frecencyFor: { $0 == "subsequence" ? 999 : 0 },
        providerWeights: [.urlClean: 112, .files: 0]
    )

    #expect(ranked.map(\.id) == ["substring", "subsequence"])
}

@Test
func providerWeightOrdersEqualTierResults() {
    let app = makeResult(id: "app:alpha", providerID: .apps, title: "Alpha")
    let file = makeResult(id: "file:alpine", providerID: .files, title: "Alpine")

    let ranked = Ranker.rank(
        [file, app],
        query: "al",
        frecencyFor: { _ in 0 },
        providerWeights: [.apps: 50, .files: 20]
    )

    #expect(ranked.map(\.id) == ["app:alpha", "file:alpine"])
}

@Test
func frecencyBreaksEqualTierAndProviderWeight() {
    let alpha = makeResult(id: "app:alpha", title: "Alpha")
    let alpine = makeResult(id: "app:alpine", title: "Alpine")

    let ranked = Ranker.rank(
        [alpha, alpine],
        query: "al",
        frecencyFor: { $0 == alpine.id ? 10 : 0 },
        providerWeights: [.apps: 50]
    )

    #expect(ranked.map(\.id) == ["app:alpine", "app:alpha"])
}

@Test
func rankingIsDeterministic() {
    let input = [
        makeResult(id: "app:2", title: "Beta", sortHint: 1),
        makeResult(id: "app:1", title: "Alpha", sortHint: 0),
        makeResult(id: "app:3", title: "Alpine", sortHint: 2)
    ]
    let rank: () -> [SearchResult] = {
        Ranker.rank(
            input,
            query: "a",
            frecencyFor: { _ in 0 },
            providerWeights: [.apps: 50]
        )
    }

    #expect(rank() == rank())
}

@Test
func emptyQueryKeepsProviderSortOrder() {
    let input = [
        makeResult(id: "app:zulu", title: "Zulu", sortHint: 0),
        makeResult(id: "app:alpha", title: "Alpha", sortHint: 1)
    ]

    let ranked = Ranker.rank(
        input,
        query: "",
        frecencyFor: { _ in 0 },
        providerWeights: [.apps: 50]
    )

    #expect(ranked.map(\.id) == ["app:zulu", "app:alpha"])
}

@Test
func webSearchSurvivesQueryItDoesNotTierMatch() {
    let webSearch = makeResult(
        id: "websearch",
        providerID: .webSearch,
        title: "Search Google for \"xyz\"",
        isFallback: true
    )

    let ranked = Ranker.rank(
        [webSearch],
        query: "totally-different-term",
        frecencyFor: { _ in 0 },
        providerWeights: [:]
    )

    #expect(ranked.map(\.id) == ["websearch"])
}

@Test
func webSearchAlwaysSortsAfterHigherScoringResult() {
    let app = makeResult(id: "app:example", providerID: .apps, title: "example")
    let webSearch = makeResult(
        id: "websearch",
        providerID: .webSearch,
        title: "irrelevant",
        keywords: ["example"],
        isFallback: true
    )

    let ranked = Ranker.rank(
        [webSearch, app],
        query: "example",
        frecencyFor: { _ in 0 },
        providerWeights: [.apps: 1, .webSearch: 999]
    )

    #expect(ranked.map(\.id) == ["app:example", "websearch"])
}

@Test
func multipleWebSearchResultsPreserveRelativeOrder() {
    let first = makeResult(id: "websearch:first", providerID: .webSearch, title: "Zulu", isFallback: true)
    let second = makeResult(id: "websearch:second", providerID: .webSearch, title: "Alpha", isFallback: true)

    let ranked = Ranker.rank(
        [first, second],
        query: "",
        frecencyFor: { _ in 0 },
        providerWeights: [:]
    )

    #expect(ranked.map(\.id) == ["websearch:first", "websearch:second"])
}

// Task 12: retention/ordering key off `isFallback`, not `providerID ==
// .webSearch` — any provider can opt in. These two mirror the webSearch
// tests above but with a non-webSearch providerID, proving the flag (not
// the ID) is what drives the behavior.
@Test
func fallbackFlagNotProviderIDGatesRetention() {
    let fallback = makeResult(
        id: "fallback",
        providerID: .customSearch,
        title: "irrelevant",
        isFallback: true
    )

    let ranked = Ranker.rank(
        [fallback],
        query: "totally-different-term",
        frecencyFor: { _ in 0 },
        providerWeights: [:]
    )

    #expect(ranked.map(\.id) == ["fallback"])
}

@Test
func fallbackFlagNotProviderIDGatesOrdering() {
    let app = makeResult(id: "app:example", providerID: .apps, title: "example")
    let fallback = makeResult(
        id: "fallback",
        providerID: .customSearch,
        title: "irrelevant",
        keywords: ["example"],
        isFallback: true
    )

    let ranked = Ranker.rank(
        [fallback, app],
        query: "example",
        frecencyFor: { _ in 0 },
        providerWeights: [.apps: 1, .customSearch: 999]
    )

    #expect(ranked.map(\.id) == ["app:example", "fallback"])
}

private nonisolated func makeResult(
    id: String,
    providerID: ProviderID = .apps,
    title: String,
    keywords: [String] = [],
    sortHint: Int = 0,
    isFallback: Bool = false
) -> SearchResult {
    SearchResult(
        id: id,
        providerID: providerID,
        title: title,
        keywords: keywords,
        action: .copyText(title),
        sortHint: sortHint,
        isFallback: isFallback
    )
}
