import Foundation
import Testing
@testable import BopopKit

@Test func largeTypePrefersCopyPayloadThenHeroThenPath() {
    let copyResult = SearchResult(
        id: "c", providerID: .clipboard, title: "Text",
        action: .copyText("hello world"), sortHint: 0)
    #expect(LargeType.text(for: copyResult) == "hello world")

    let heroOnly = SearchResult(
        id: "h", providerID: .urlClean, title: "Cleaned",
        action: .openURL("https://x.com"),
        hero: HeroContent(left: "long-url", right: "https://x.com"), sortHint: 0)
    #expect(LargeType.text(for: heroOnly) == "https://x.com")

    let file = SearchResult(
        id: "f", providerID: .files, title: "Notes.txt",
        action: .openFile("/Users/x/Notes.txt"), sortHint: 0)
    #expect(LargeType.text(for: file) == "Notes.txt")

    let modeEntry = SearchResult(
        id: "m", providerID: .commands, title: "Snippets…",
        action: .enterMode(.snippets), sortHint: 0)
    #expect(LargeType.text(for: modeEntry) == nil)
    #expect(LargeType.text(for: nil) == nil)
}

@Test func largeTypeUsesSecondaryCopyWhenPrimaryIsNot() {
    let result = SearchResult(
        id: "s", providerID: .dictionary, title: "Define",
        action: .openURL("dict://word"),
        secondaryActions: [.copyText("the definition")], sortHint: 0)
    #expect(LargeType.text(for: result) == "the definition")
}

/// The overlay renders at most 3 lines, but it used to size itself by laying
/// out the whole copy payload — up to a 100 KB clipboard entry — which cost
/// 0.34 s of main-thread layout and produced an 18,000-point panel frame.
@Test func largeTypeCapsRunawayCopyPayloads() throws {
    // ClipboardStore.maximumTextSize — a max-size clipboard entry.
    let huge = String(repeating: "x", count: 100_000)
    let result = SearchResult(
        id: "c", providerID: .clipboard, title: "Text",
        action: .copyText(huge), sortHint: 0)

    let text = try #require(LargeType.text(for: result))
    #expect(text.count == LargeType.characterLimit + 1) // + the ellipsis
    #expect(text.hasSuffix("…"))

    // Text that fits is returned untouched, ellipsis and all.
    let short = SearchResult(
        id: "s", providerID: .clipboard, title: "Text",
        action: .copyText("still short"), sortHint: 0)
    #expect(LargeType.text(for: short) == "still short")
}

/// A hero pane can carry provider-built text too (translations especially).
@Test func largeTypeCapsHeroText() throws {
    let long = String(repeating: "translated ", count: 500)
    let result = SearchResult(
        id: "t", providerID: .translation, title: "T",
        action: .enterMode(.general),
        hero: HeroContent(left: "source", right: long), sortHint: 0)

    let text = try #require(LargeType.text(for: result))
    #expect(text.count == LargeType.characterLimit + 1)
}
