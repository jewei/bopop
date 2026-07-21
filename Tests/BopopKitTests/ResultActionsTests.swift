import Foundation
import Testing
@testable import BopopKit

@Test func fileResultGetsOpenRevealQuickLookLargeType() {
    let file = SearchResult(
        id: "f", providerID: .files, title: "Notes.txt",
        action: .openFile("/Users/x/Notes.txt"), sortHint: 0)
    let items = ResultActions.items(for: file)
    #expect(items.map(\.kind) == [.primary, .reveal, .quickLook, .largeType])
    #expect(items[0].title == "Open")
    #expect(items[0].shortcut == "⏎")
    #expect(items[1].title == "Reveal in Finder")
    #expect(items[1].shortcut == "⌘⏎")
    #expect(items[2].title == "Quick Look")
    #expect(items[2].shortcut == "⌘Y")
    #expect(items[3].title == "Large Type")
    #expect(items[3].shortcut == "⌘L")
}

@Test func copyPrimaryIsNotDuplicatedAsCopyRow() {
    let clip = SearchResult(
        id: "c", providerID: .clipboard, title: "Text",
        action: .copyText("hello"), sortHint: 0)
    let items = ResultActions.items(for: clip)
    // copyText payload also gives it a Large Type representation.
    #expect(items.map(\.kind) == [.primary, .largeType])
    #expect(items[0].title == "Copy")
}

@Test func secondaryCopyGetsItsOwnRow() {
    let dict = SearchResult(
        id: "d", providerID: .dictionary, title: "Define",
        action: .openURL("dict://word"),
        secondaryActions: [.copyText("the definition")], sortHint: 0)
    let items = ResultActions.items(for: dict)
    #expect(items.map(\.kind) == [.primary, .copy, .largeType])
    #expect(items[1].title == "Copy")
    #expect(items[1].shortcut == "⌘C")
}

@Test func modeEntryGetsOnlySelect() {
    let mode = SearchResult(
        id: "m", providerID: .commands, title: "Snippets…",
        action: .enterMode(.snippets), sortHint: 0)
    let items = ResultActions.items(for: mode)
    #expect(items.map(\.kind) == [.primary])
    #expect(items[0].title == "Select")
}

@Test func verbsMatchFooterVocabulary() {
    #expect(ResultActions.verb(for: .openApp("/a")) == "open")
    #expect(ResultActions.verb(for: .openFile("/f")) == "open")
    #expect(ResultActions.verb(for: .openURL("https://x")) == "open")
    #expect(ResultActions.verb(for: .copyText("t")) == "copy")
    #expect(ResultActions.verb(for: .clearClipboardHistory) == "clear")
    #expect(ResultActions.verb(for: .runScript("/s")) == "run")
    #expect(ResultActions.verb(for: .enterMode(.apps)) == "select")
    #expect(ResultActions.verb(for: .downloadTranslation) == "download")
    #expect(ResultActions.verb(for: .revealFile("/f")) == "reveal")
}

@Test func hasCopyActionSeesPrimaryAndSecondary() {
    let primary = SearchResult(
        id: "p", providerID: .clipboard, title: "T",
        action: .copyText("x"), sortHint: 0)
    let secondary = SearchResult(
        id: "s", providerID: .calculator, title: "42",
        action: .enterMode(.general),
        secondaryActions: [.copyText("42")], sortHint: 0)
    let none = SearchResult(
        id: "n", providerID: .apps, title: "Finder",
        action: .openApp("/System/Library/CoreServices/Finder.app"), sortHint: 0)
    #expect(ResultActions.hasCopyAction(primary))
    #expect(ResultActions.hasCopyAction(secondary))
    #expect(!ResultActions.hasCopyAction(none))
}
