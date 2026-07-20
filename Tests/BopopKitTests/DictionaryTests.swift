import Foundation
import Testing
@testable import BopopKit

@Test func dictionaryTriggerParsesDefinePrefixes() {
    #expect(DictionaryQuery.word(from: "define serendipity") == "serendipity")
    #expect(DictionaryQuery.word(from: "DEF Serendipity") == "Serendipity")
    #expect(DictionaryQuery.word(from: "define ") == nil)
    #expect(DictionaryQuery.word(from: "definitely not") == nil)
    #expect(DictionaryQuery.word(from: "defer x") == nil)
    #expect(DictionaryQuery.word(from: "serendipity") == nil)
}

@MainActor
@Test func dictionaryProviderBuildsHeroFromLookup() async throws {
    let definition = "serendipity | noun: the occurrence of events by chance in a happy way."
    let provider = DictionaryProvider(lookup: { _ in definition })
    let results = try await provider.results(
        for: ParsedQuery(mode: .general, term: "define serendipity"))
    let row = try #require(results.first)
    #expect(row.providerID == .dictionary)
    let hero = try #require(row.hero)
    #expect(hero.left == "serendipity")
    #expect(hero.right.count <= 121)  // 120 chars + ellipsis
    if case .openURL(let urlString) = row.action {
        #expect(urlString == "dict://serendipity")
    } else { Issue.record("expected openURL dict://") }
    #expect(row.secondaryActions == [.copyText(definition)])
}

@MainActor
@Test func dictionaryProviderIsQuietWithoutMatch() async throws {
    let provider = DictionaryProvider(lookup: { _ in nil })
    let noDefinition = try await provider.results(
        for: ParsedQuery(mode: .general, term: "define qzxv"))
    #expect(noDefinition.isEmpty)
    let wrongMode = try await provider.results(
        for: ParsedQuery(mode: .clipboard, term: "define x"))
    #expect(wrongMode.isEmpty)
    #expect(Ranker.defaultWeights[.dictionary] == 111)
}

@MainActor
@Test func dictionaryURLEncodesTheWord() async throws {
    let provider = DictionaryProvider(lookup: { _ in "café | noun" })
    let results = try await provider.results(
        for: ParsedQuery(mode: .general, term: "define café au lait"))
    if case .openURL(let urlString) = try #require(results.first).action {
        #expect(urlString == "dict://caf%C3%A9%20au%20lait")
    } else { Issue.record("expected openURL") }
}
