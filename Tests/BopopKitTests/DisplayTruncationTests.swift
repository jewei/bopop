import Testing
@testable import BopopKit

@Test func displayTruncationReturnsShortTextUnchanged() {
    #expect(DisplayTruncation.firstLine("hello", limit: 60) == "hello")
}

@Test func displayTruncationDoesNotAppendEllipsisAtExactLimit() {
    let text = String(repeating: "x", count: 60)
    #expect(DisplayTruncation.firstLine(text, limit: 60) == text)
}

@Test func displayTruncationAppendsEllipsisPastLimit() {
    let text = String(repeating: "x", count: 61)
    #expect(DisplayTruncation.firstLine(text, limit: 60) == String(repeating: "x", count: 60) + "…")
}

@Test func displayTruncationTakesOnlyFirstLine() {
    #expect(DisplayTruncation.firstLine("line1\nline2\nline3", limit: 60) == "line1")
}

@Test func displayTruncationTrimsWhitespaceAroundFirstLine() {
    #expect(DisplayTruncation.firstLine("  padded line  \nrest", limit: 60) == "padded line")
}

@Test func displayTruncationHandlesEmptyText() {
    #expect(DisplayTruncation.firstLine("", limit: 60) == "")
}

@Test func displayTruncationIsGraphemeClusterSafe() {
    // A family emoji is four Unicode scalars joined by zero-width joiners
    // but exactly one Swift Character (grapheme cluster) — a naive
    // UTF-16/scalar-based truncation would risk slicing through one,
    // producing a broken glyph or an ill-formed String. `.count`/`.prefix`
    // on String operate on grapheme clusters, so this must truncate
    // cleanly at a character boundary.
    let family = "👨‍👩‍👧‍👦"
    let text = String(repeating: family, count: 65)

    let result = DisplayTruncation.firstLine(text, limit: 60)

    #expect(result == String(repeating: family, count: 60) + "…")
    #expect(result.count == 61)
}
