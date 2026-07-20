import Testing
@testable import BopopKit

@MainActor
@Test func emojiCatalogLoadsSanityCheckedEntries() {
    let catalog = EmojiCatalog()

    #expect(catalog.entries.count > 1500)

    let fire = catalog.entries.first { $0.char == "🔥" }
    #expect(fire?.name == "fire")
    #expect(fire?.keywords.contains("flame") == true)
}

@MainActor
@Test func emojiCatalogHasNoSkinToneVariants() {
    let catalog = EmojiCatalog()
    let skinToneScalars: Set<Unicode.Scalar> = [
        "\u{1F3FB}", "\u{1F3FC}", "\u{1F3FD}", "\u{1F3FE}", "\u{1F3FF}"
    ]

    let hasSkinTone = catalog.entries.contains { entry in
        entry.char.unicodeScalars.contains { skinToneScalars.contains($0) }
    }
    #expect(!hasSkinTone)
}

@MainActor
@Test func emojiProviderIgnoresOtherModes() async throws {
    let provider = EmojiProvider(catalog: EmojiCatalog(), frecencyFor: { _ in [:] })
    let results = try await provider.results(for: ParsedQuery(mode: .general, term: "fire"))
    #expect(results.isEmpty)
}

@MainActor
@Test func emojiProviderEmptyTermReturnsFullCatalogInCatalogOrderWhenTied() async throws {
    let catalog = EmojiCatalog()
    let provider = EmojiProvider(catalog: catalog, frecencyFor: { _ in [:] })

    let results = try await provider.results(for: ParsedQuery(mode: .emoji, term: ""))

    #expect(results.count == catalog.entries.count)
    #expect(results.map(\.id) == catalog.entries.map(\.char))
}

@MainActor
@Test func emojiProviderEmptyTermLiftsFrecentEntryToFront() async throws {
    let catalog = EmojiCatalog()
    let favorite = catalog.entries[600]
    let provider = EmojiProvider(
        catalog: catalog,
        frecencyFor: { ids in
            ids.reduce(into: [:]) { $0[$1] = $1 == favorite.char ? 10 : 0 }
        }
    )

    let results = try await provider.results(for: ParsedQuery(mode: .emoji, term: ""))

    #expect(results.count == catalog.entries.count)
    #expect(results.first?.id == favorite.char)
}

// Task 9: a nonempty term now pre-filters entries by Ranker tier
// (name+keywords) before building a SearchResult for each, rather than
// mapping the whole ~1900-entry catalog on every keystroke and relying
// entirely on the caller's later Ranker.rank pass to discard the rest.
@MainActor
@Test func emojiProviderNonEmptyTermPreFiltersByNameOrKeywordTier() async throws {
    let catalog = EmojiCatalog()
    let provider = EmojiProvider(catalog: catalog, frecencyFor: { _ in [:] })

    let results = try await provider.results(for: ParsedQuery(mode: .emoji, term: "fire"))

    #expect(results.count < catalog.entries.count)
    #expect(results.contains { $0.id == "🔥" })
}

@MainActor
@Test func emojiProviderPreFilterIsRankerNoOp() async throws {
    let catalog = EmojiCatalog()
    let provider = EmojiProvider(catalog: catalog, frecencyFor: { _ in [:] })
    let term = "flame"

    let filtered = try await provider.results(for: ParsedQuery(mode: .emoji, term: term))

    // Reconstruct what the provider would have returned before the
    // pre-filter (the whole catalog, unfiltered), using the same result
    // shape EmojiProvider builds, and rank both through Ranker.rank the
    // way QueryEngine does. The pre-filter is meant to be a pure hot-path
    // optimization — Ranker discards the same rows either way — so ranking
    // the (much smaller) filtered set must equal ranking the full catalog.
    let unfiltered = catalog.entries.enumerated().map { index, entry in
        SearchResult(
            id: entry.char,
            providerID: .emoji,
            title: "\(entry.char)  \(entry.name)",
            icon: .none,
            keywords: [entry.name] + entry.keywords,
            action: .copyText(entry.char),
            sortHint: index
        )
    }

    let rankedFiltered = Ranker.rank(
        filtered, query: term, frecencyFor: { _ in 0 }, providerWeights: Ranker.defaultWeights
    )
    let rankedUnfiltered = Ranker.rank(
        unfiltered, query: term, frecencyFor: { _ in 0 }, providerWeights: Ranker.defaultWeights
    )

    #expect(!rankedFiltered.isEmpty)
    #expect(rankedFiltered.count < catalog.entries.count)
    #expect(rankedFiltered.map(\.id) == rankedUnfiltered.map(\.id))
}

@MainActor
@Test func emojiProviderResultShapeCopiesChar() async throws {
    let catalog = EmojiCatalog()
    let provider = EmojiProvider(catalog: catalog, frecencyFor: { _ in [:] })

    let results = try await provider.results(for: ParsedQuery(mode: .emoji, term: "fire"))
    let fire = try #require(results.first { $0.id == "🔥" })

    #expect(fire.title == "🔥  fire")
    #expect(fire.icon == .none)
    #expect(fire.action == .copyText("🔥"))
    #expect(fire.keywords.first == "fire")
    #expect(fire.keywords.contains("flame"))
}

@MainActor
@Test func emojiSearchThroughRankerPlacesFireAmongTopResultsForPrefix() async throws {
    let catalog = EmojiCatalog()
    let provider = EmojiProvider(catalog: catalog, frecencyFor: { _ in [:] })
    let query = ParsedQuery(mode: .emoji, term: "fir")

    let results = try await provider.results(for: query)
    let ranked = Ranker.rank(
        results,
        query: query.term,
        frecencyFor: { _ in 0 },
        providerWeights: Ranker.defaultWeights
    )

    // "fir" prefix-matches several fire-related emoji (fire engine, firefighter,
    // firecracker, ...) that tie with 🔥 on match tier, provider weight, and
    // frecency — Ranker then tie-breaks on title text, which leads with the
    // glyph rather than the name. 🔥 lands within the top 10 rather than
    // strictly first; a search on its unique "flame" keyword (below) is the
    // deterministic exact-match case.
    #expect(ranked.prefix(10).map(\.id).contains("🔥"))
}

@MainActor
@Test func emojiSearchThroughRankerRanksUniqueKeywordFirst() async throws {
    let catalog = EmojiCatalog()
    let provider = EmojiProvider(catalog: catalog, frecencyFor: { _ in [:] })
    let query = ParsedQuery(mode: .emoji, term: "flame")

    let results = try await provider.results(for: query)
    let ranked = Ranker.rank(
        results,
        query: query.term,
        frecencyFor: { _ in 0 },
        providerWeights: Ranker.defaultWeights
    )

    #expect(ranked.first?.id == "🔥")
}
