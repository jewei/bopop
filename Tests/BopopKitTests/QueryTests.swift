import Testing
@testable import BopopKit

@Test
func queryParserRecognizesFilePrefix() {
    #expect(
        QueryParser.parse(raw: "f budget", stickyMode: .general)
            == ParsedQuery(mode: .fileSearch, term: "budget")
    )
    #expect(
        QueryParser.parse(raw: "F  x", stickyMode: .general)
            == ParsedQuery(mode: .fileSearch, term: "x")
    )
}

@Test
func queryParserRequiresSpaceAfterFilePrefix() {
    #expect(
        QueryParser.parse(raw: "f", stickyMode: .general)
            == ParsedQuery(mode: .general, term: "f")
    )
}

/// Sticky mode takes the text literally — no prefix re-parsing — but still
/// trims, exactly like every general-mode branch.
@Test
func stickyQueryModeDoesNotReparsePrefixesButStillTrims() {
    #expect(
        QueryParser.parse(raw: "  f budget  ", stickyMode: .fileSearch)
            == ParsedQuery(mode: .fileSearch, term: "f budget")
    )
    #expect(
        QueryParser.parse(raw: "f note", stickyMode: .clipboard)
            == ParsedQuery(mode: .clipboard, term: "f note")
    )
}

/// Ranker folds case and diacritics but never trims, so an untrimmed sticky
/// term made one trailing space tier-mismatch every candidate — the list went
/// blank mid-word while the user was still typing.
@Test
func stickyModeTrailingSpaceStillMatches() {
    let query = QueryParser.parse(raw: "safari ", stickyMode: .apps)
    #expect(query.term == "safari")
    #expect(Ranker.tier(query: query.term, candidate: "Safari") == .exact)

    let safari = SearchResult(
        id: "app:safari",
        providerID: .apps,
        title: "Safari",
        action: .openApp("/Applications/Safari.app"),
        sortHint: 0
    )
    let ranked = Ranker.rank(
        [safari],
        query: query.term,
        frecencyFor: { _ in 0 },
        providerWeights: [.apps: 50]
    )
    #expect(ranked.map(\.id) == ["app:safari"])
}

@Test func queryParserEmojiPrefix() {
    #expect(QueryParser.parse(raw: ":fire", stickyMode: .general)
        == ParsedQuery(mode: .emoji, term: "fire"))
    #expect(QueryParser.parse(raw: ":fire ", stickyMode: .general)
        == ParsedQuery(mode: .emoji, term: "fire"))
    #expect(QueryParser.parse(raw: ":", stickyMode: .general).mode == .general)
    #expect(QueryParser.parse(raw: "t hello", stickyMode: .general)
        == ParsedQuery(mode: .translation, term: "hello"))
}
