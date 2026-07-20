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
