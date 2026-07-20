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
    let provider = EmojiProvider(catalog: EmojiCatalog(), frecencyFor: { _ in 0 })
    let results = try await provider.results(for: ParsedQuery(mode: .general, term: "fire"))
    #expect(results.isEmpty)
}

@MainActor
@Test func emojiProviderEmptyTermReturnsFullCatalogInCatalogOrderWhenTied() async throws {
    let catalog = EmojiCatalog()
    let provider = EmojiProvider(catalog: catalog, frecencyFor: { _ in 0 })

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
        frecencyFor: { $0 == favorite.char ? 10 : 0 }
    )

    let results = try await provider.results(for: ParsedQuery(mode: .emoji, term: ""))

    #expect(results.count == catalog.entries.count)
    #expect(results.first?.id == favorite.char)
}

@MainActor
@Test func emojiProviderNonEmptyTermReturnsAllEntries() async throws {
    let catalog = EmojiCatalog()
    let provider = EmojiProvider(catalog: catalog, frecencyFor: { _ in 0 })

    let results = try await provider.results(for: ParsedQuery(mode: .emoji, term: "fire"))

    #expect(results.count == catalog.entries.count)
}

@MainActor
@Test func emojiProviderResultShapeCopiesChar() async throws {
    let catalog = EmojiCatalog()
    let provider = EmojiProvider(catalog: catalog, frecencyFor: { _ in 0 })

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
    let provider = EmojiProvider(catalog: catalog, frecencyFor: { _ in 0 })
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
    let provider = EmojiProvider(catalog: catalog, frecencyFor: { _ in 0 })
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
