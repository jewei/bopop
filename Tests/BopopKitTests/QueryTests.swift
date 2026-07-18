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

@Test
func stickyQueryModePassesRawTextVerbatim() {
    #expect(
        QueryParser.parse(raw: "  f budget  ", stickyMode: .fileSearch)
            == ParsedQuery(mode: .fileSearch, term: "  f budget  ")
    )
    #expect(
        QueryParser.parse(raw: "f note", stickyMode: .clipboard)
            == ParsedQuery(mode: .clipboard, term: "f note")
    )
}

@Test
func escapePolicyFollowsClearExitCloseChain() {
    #expect(
        EscapePolicy.action(textIsEmpty: false, stickyMode: .general) == .clearText
    )
    #expect(
        EscapePolicy.action(textIsEmpty: false, stickyMode: .fileSearch) == .clearText
    )
    #expect(
        EscapePolicy.action(textIsEmpty: true, stickyMode: .clipboard) == .exitMode
    )
    #expect(
        EscapePolicy.action(textIsEmpty: true, stickyMode: .general) == .closePanel
    )
}
