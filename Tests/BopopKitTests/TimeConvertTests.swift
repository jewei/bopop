import Foundation
import Testing
@testable import BopopKit

private let fixedNow = Date(timeIntervalSince1970: 1_760_000_000) // 2025-10-09 08:53:20 UTC
private let localZone = TimeZone(identifier: "Asia/Kuala_Lumpur")!

@Test func timeParserResolvesBareTimeWithAbbreviation() throws {
    let result = try #require(TimeQueryParser.parse("9am eastern", now: fixedNow, localZone: localZone))
    #expect(result.sourceDescription == "Thursday, 9 October, 9:00 AM, GMT-4")
    #expect(result.localDescription == "October 9, 2025 at 21:00")
    #expect(result.instant == Date(timeIntervalSince1970: 1_760_014_800))
}

@Test func timeParserResolvesExplicitDateWithCode() throws {
    let result = try #require(TimeQueryParser.parse("oct 13 9pm PST", now: fixedNow, localZone: localZone))
    #expect(result.sourceDescription == "Monday, 13 October, 9:00 PM, GMT-7")
    #expect(result.localDescription == "October 14, 2025 at 12:00")
    #expect(result.instant == Date(timeIntervalSince1970: 1_760_414_400))
}

@Test func timeParserResolvesCurrentTimeInZone() throws {
    let result = try #require(TimeQueryParser.parse("time in tokyo", now: fixedNow, localZone: localZone))
    #expect(result.sourceDescription == "Tokyo, GMT+9")
    #expect(result.localDescription == "5:53 PM")
    #expect(result.instant == fixedNow)
}

@Test func timeParserResolvesTokenTimeSuffixShape() throws {
    let result = try #require(TimeQueryParser.parse("tokyo time", now: fixedNow, localZone: localZone))
    #expect(result.sourceDescription == "Tokyo, GMT+9")
}

@Test func timeParserResolvesRelativeDayWord() throws {
    let result = try #require(TimeQueryParser.parse("tomorrow 3pm london", now: fixedNow, localZone: localZone))
    #expect(result.sourceDescription == "Friday, 10 October, 3:00 PM, GMT+1")
    #expect(result.localDescription == "October 10, 2025 at 22:00")
    #expect(result.instant == Date(timeIntervalSince1970: 1_760_104_800))
}

@Test func timeParserRejectsBareZoneWord() {
    #expect(TimeQueryParser.parse("eastern", now: fixedNow, localZone: localZone) == nil)
}

@Test func timeParserRejectsUnrelatedText() {
    #expect(TimeQueryParser.parse("hello world", now: fixedNow, localZone: localZone) == nil)
}

@Test func timeParserRejectsBareTimeWithNoZone() {
    #expect(TimeQueryParser.parse("9am", now: fixedNow, localZone: localZone) == nil)
}

@Test func timeParserRejectsEmptyTerm() {
    #expect(TimeQueryParser.parse("   ", now: fixedNow, localZone: localZone) == nil)
}

@Test func timeParserRejectsUnsupportedDateShapes() {
    // Weekday and numeric-date phrases would silently resolve to the wrong
    // day via the time-only fallback — they must refuse instead.
    #expect(TimeQueryParser.parse("monday 3pm eastern", now: fixedNow, localZone: localZone) == nil)
    #expect(TimeQueryParser.parse("next fri 9am PST", now: fixedNow, localZone: localZone) == nil)
    #expect(TimeQueryParser.parse("10/13 9am eastern", now: fixedNow, localZone: localZone) == nil)
    #expect(TimeQueryParser.parse("13-10 9am eastern", now: fixedNow, localZone: localZone) == nil)
}

// MARK: - Half-hour / non-whole-hour GMT offsets

@Test func timeParserIncludesMinutesForHalfHourOffset() throws {
    let result = try #require(TimeQueryParser.parse("9am ist", now: fixedNow, localZone: localZone))
    #expect(result.sourceDescription == "Thursday, 9 October, 9:00 AM, GMT+5:30")
}

@Test func timeParserKeepsWholeHourOffsetUnchanged() throws {
    let result = try #require(TimeQueryParser.parse("9am eastern", now: fixedNow, localZone: localZone))
    #expect(result.sourceDescription.hasSuffix("GMT-4"))
}

@Test func timeParserIncludesMinutesForNegativeHalfHourOffset() throws {
    let winterNow = Date(timeIntervalSince1970: 1_768_478_400) // 2026-01-15 12:00 UTC
    let result = try #require(TimeQueryParser.parse("time in st johns", now: winterNow, localZone: localZone))
    #expect(result.sourceDescription == "St Johns, GMT-3:30")
}

// MARK: - DST awareness (America/New_York flips offset by date)

@Test func timeParserUsesDaylightOffsetInOctober() throws {
    let result = try #require(TimeQueryParser.parse("9am eastern", now: fixedNow, localZone: localZone))
    #expect(result.sourceDescription.hasSuffix("GMT-4"))
}

@Test func timeParserUsesStandardOffsetInJanuary() throws {
    let winterNow = Date(timeIntervalSince1970: 1_768_478_400) // 2026-01-15 12:00 UTC
    let result = try #require(TimeQueryParser.parse("9am eastern", now: winterNow, localZone: localZone))
    #expect(result.sourceDescription == "Thursday, 15 January, 9:00 AM, GMT-5")
    #expect(result.localDescription == "January 15, 2026 at 22:00")
}

// MARK: - Provider

@MainActor
@Test func timeProviderReturnsHeroResultOnMatch() async throws {
    let provider = TimeProvider(now: { fixedNow }, localTimeZone: { localZone })
    let query = ParsedQuery(mode: .general, term: "9am eastern")

    let results = try await provider.results(for: query)

    #expect(results.count == 1)
    let result = try #require(results.first)
    #expect(result.id == "time")
    #expect(result.providerID == .time)
    #expect(result.keywords == [query.term])
    #expect(result.action == .copyText("October 9, 2025 at 21:00"))
    #expect(result.sortHint == 0)

    let hero = try #require(result.hero)
    // The GMT offset lives only in the badge; the value text drops it.
    #expect(hero.left == "Thursday, 9 October, 9:00 AM")
    #expect(hero.leftBadge == "GMT-4")
    #expect(hero.right == "October 9, 2025 at 21:00")
    #expect(hero.rightBadge == "Your Time")
}

@MainActor
@Test func timeProviderReturnsEmptyOnParseMiss() async throws {
    let provider = TimeProvider(now: { fixedNow }, localTimeZone: { localZone })
    let results = try await provider.results(for: ParsedQuery(mode: .general, term: "hello world"))
    #expect(results.isEmpty)
}

@MainActor
@Test func timeProviderIgnoresOtherModes() async throws {
    let provider = TimeProvider(now: { fixedNow }, localTimeZone: { localZone })
    let results = try await provider.results(for: ParsedQuery(mode: .fileSearch, term: "9am eastern"))
    #expect(results.isEmpty)
}
