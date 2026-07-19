import Foundation

public nonisolated struct TimeConversion: Equatable, Sendable {
    public let sourceDescription: String
    public let localDescription: String
    public let instant: Date

    public init(sourceDescription: String, localDescription: String, instant: Date) {
        self.sourceDescription = sourceDescription
        self.localDescription = localDescription
        self.instant = instant
    }
}

public nonisolated enum TimeQueryParser {
    /// Parses phrases like "9am eastern", "oct 13 9pm PST", "time in tokyo",
    /// or "tomorrow 3pm london". Returns nil when no recognizable timezone
    /// token is present (bare times/expressions are left to other providers).
    public static func parse(_ term: String, now: Date, localZone: TimeZone) -> TimeConversion? {
        let trimmed = term.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }
        let lower = trimmed.lowercased()

        if lower.hasPrefix("time in ") {
            let token = String(trimmed.dropFirst("time in ".count))
                .trimmingCharacters(in: .whitespaces)
            guard !token.isEmpty, let zone = resolveZone(for: token) else {
                return nil
            }
            return currentTimeConversion(zone: zone, token: token, now: now)
        }

        if lower.hasSuffix(" time") {
            let token = String(trimmed.dropLast(" time".count))
                .trimmingCharacters(in: .whitespaces)
            if !token.isEmpty, let zone = resolveZone(for: token) {
                return currentTimeConversion(zone: zone, token: token, now: now)
            }
        }

        guard let stripped = stripTrailingZoneToken(from: trimmed) else {
            return nil
        }
        let phrase = stripped.remainder.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !phrase.isEmpty else {
            return nil
        }

        return parseDateTimePhrase(phrase, zone: stripped.zone, now: now, localZone: localZone)
    }

    // MARK: - Zone token table

    /// Abbreviations and region words → IANA identifier.
    private static let zoneAbbreviations: [String: String] = [
        "est": "America/New_York", "edt": "America/New_York", "eastern": "America/New_York",
        "cst": "America/Chicago", "cdt": "America/Chicago", "central": "America/Chicago",
        "mst": "America/Denver", "mdt": "America/Denver", "mountain": "America/Denver",
        "pst": "America/Los_Angeles", "pdt": "America/Los_Angeles", "pacific": "America/Los_Angeles",
        "gmt": "GMT", "utc": "GMT",
        "bst": "Europe/London",
        "cet": "Europe/Paris", "cest": "Europe/Paris",
        "jst": "Asia/Tokyo",
        "kst": "Asia/Seoul",
        "ist": "Asia/Kolkata",
        "sgt": "Asia/Singapore",
        "hkt": "Asia/Hong_Kong",
        "aest": "Australia/Sydney", "aedt": "Australia/Sydney",
        "myt": "Asia/Kuala_Lumpur"
    ]

    /// City / short-form aliases → IANA identifier. (Note: corrects an apparent
    /// transcription error in the source plan, which listed nyc/new york under
    /// America/Los_Angeles alongside sf/san francisco — geographically that
    /// can't be right, so nyc/new york route to America/New_York here.)
    private static let cityAliases: [String: String] = [
        "nyc": "America/New_York", "new york": "America/New_York",
        "sf": "America/Los_Angeles", "san francisco": "America/Los_Angeles", "la": "America/Los_Angeles",
        "london": "Europe/London",
        "paris": "Europe/Paris", "berlin": "Europe/Paris",
        "tokyo": "Asia/Tokyo",
        "seoul": "Asia/Seoul",
        "sydney": "Australia/Sydney",
        "singapore": "Asia/Singapore",
        "hong kong": "Asia/Hong_Kong",
        "kl": "Asia/Kuala_Lumpur", "kuala lumpur": "Asia/Kuala_Lumpur",
        "taipei": "Asia/Taipei",
        "shanghai": "Asia/Shanghai", "beijing": "Asia/Shanghai",
        "dubai": "Asia/Dubai",
        "mumbai": "Asia/Kolkata", "delhi": "Asia/Kolkata"
    ]

    /// Every known IANA identifier's last path component, spaced and lowercased,
    /// e.g. "Asia/Kuala_Lumpur" → "kuala lumpur". Fills in anything the two
    /// curated tables above don't already cover.
    private static let autoAliases: [String: String] = {
        var map: [String: String] = [:]
        for identifier in TimeZone.knownTimeZoneIdentifiers {
            guard let last = identifier.split(separator: "/").last else {
                continue
            }
            let key = last.replacingOccurrences(of: "_", with: " ").lowercased()
            map[key] = identifier
        }
        return map
    }()

    private static func resolveZone(for token: String) -> TimeZone? {
        let key = token.lowercased().trimmingCharacters(in: .whitespaces)
        guard !key.isEmpty else {
            return nil
        }
        guard let identifier = zoneAbbreviations[key] ?? cityAliases[key] ?? autoAliases[key] else {
            return nil
        }
        return TimeZone(identifier: identifier)
    }

    /// Tries the trailing 3, 2, then 1 words of `text` as a zone token (longest
    /// match wins, so "hong kong" beats a stray single-word match on "kong").
    private static func stripTrailingZoneToken(
        from text: String
    ) -> (zone: TimeZone, remainder: String, token: String)? {
        let words = text.split(separator: " ").map(String.init)
        guard !words.isEmpty else {
            return nil
        }
        let maxWidth = min(3, words.count)
        for width in stride(from: maxWidth, through: 1, by: -1) {
            let candidate = words.suffix(width).joined(separator: " ")
            if let zone = resolveZone(for: candidate) {
                let remainder = words.dropLast(width).joined(separator: " ")
                return (zone, remainder, candidate)
            }
        }
        return nil
    }

    // MARK: - Shape 1: "time in <token>" / "<token> time"

    private static func currentTimeConversion(zone: TimeZone, token: String, now: Date) -> TimeConversion {
        let place = placeName(for: token)
        let sourceDescription = "\(place), \(gmtOffsetString(for: zone, instant: now))"

        let timeFormatter = DateFormatter()
        timeFormatter.locale = Locale(identifier: "en_US_POSIX")
        timeFormatter.timeZone = zone
        timeFormatter.dateFormat = "h:mm a"
        let localDescription = timeFormatter.string(from: now)

        return TimeConversion(sourceDescription: sourceDescription, localDescription: localDescription, instant: now)
    }

    private static func placeName(for token: String) -> String {
        token.split(separator: " ").map { $0.capitalized }.joined(separator: " ")
    }

    // MARK: - Shape 2: "<datetime phrase> <zone token>"

    /// NSDataDetector always resolves relative wording ("today"/"tomorrow") and
    /// missing components against the *real* wall clock (TimeZone.current /
    /// Date()), which is unusable for deterministic tests. So this only trusts
    /// the detector for the literal time-of-day it read (decoded back out via
    /// the same ambient zone it encoded with — a lossless round trip regardless
    /// of what that ambient zone actually is) and re-derives the calendar day
    /// itself from the injected `now`, rebased into the source zone.
    private static func parseDateTimePhrase(
        _ phrase: String,
        zone: TimeZone,
        now: Date,
        localZone: TimeZone
    ) -> TimeConversion? {
        // Weekday phrases ("next monday 3pm") and numeric dates ("10/13 9am")
        // would fall through to the time-only path and silently answer with
        // the wrong day — refuse them instead of guessing.
        guard !containsUnsupportedDateToken(phrase.lowercased()) else {
            return nil
        }
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue) else {
            return nil
        }
        let range = NSRange(phrase.startIndex..<phrase.endIndex, in: phrase)
        guard let match = detector.firstMatch(in: phrase, options: [], range: range),
              let detected = match.date else {
            return nil
        }

        var ambientCalendar = Calendar(identifier: .gregorian)
        ambientCalendar.timeZone = TimeZone.current
        ambientCalendar.locale = Locale(identifier: "en_US_POSIX")
        let detectedParts = ambientCalendar.dateComponents([.month, .day, .hour, .minute], from: detected)
        guard let hour = detectedParts.hour, let minute = detectedParts.minute else {
            return nil
        }

        var sourceCalendar = Calendar(identifier: .gregorian)
        sourceCalendar.timeZone = zone
        sourceCalendar.locale = Locale(identifier: "en_US_POSIX")
        let nowParts = sourceCalendar.dateComponents([.year, .month, .day], from: now)

        let lowerPhrase = phrase.lowercased()
        let year: Int
        let month: Int
        let day: Int

        if let dayOffset = relativeDayOffset(in: lowerPhrase) {
            let nowDay = sourceCalendar.date(from: nowParts) ?? now
            let shifted = sourceCalendar.date(byAdding: .day, value: dayOffset, to: nowDay) ?? nowDay
            let shiftedParts = sourceCalendar.dateComponents([.year, .month, .day], from: shifted)
            year = shiftedParts.year ?? nowParts.year ?? 1970
            month = shiftedParts.month ?? 1
            day = shiftedParts.day ?? 1
        } else if containsMonthName(lowerPhrase), let detectedMonth = detectedParts.month,
                  let detectedDay = detectedParts.day {
            month = detectedMonth
            day = detectedDay
            let candidateYear = nowParts.year ?? 1970
            var candidateComponents = DateComponents(year: candidateYear, month: month, day: day)
            let nowInstant = sourceCalendar.date(from: nowParts) ?? now
            if let candidateDate = sourceCalendar.date(from: candidateComponents), candidateDate < nowInstant {
                candidateComponents.year = candidateYear + 1
            }
            year = candidateComponents.year ?? candidateYear
        } else {
            year = nowParts.year ?? 1970
            month = nowParts.month ?? 1
            day = nowParts.day ?? 1
        }

        var targetComponents = DateComponents()
        targetComponents.year = year
        targetComponents.month = month
        targetComponents.day = day
        targetComponents.hour = hour
        targetComponents.minute = minute

        guard let instant = sourceCalendar.date(from: targetComponents) else {
            return nil
        }

        return TimeConversion(
            sourceDescription: formatSourceDescription(instant: instant, zone: zone),
            localDescription: formatLocalDescription(instant: instant, zone: localZone),
            instant: instant
        )
    }

    private static let monthNames: Set<String> = [
        "jan", "january", "feb", "february", "mar", "march", "apr", "april", "may",
        "jun", "june", "jul", "july", "aug", "august", "sep", "sept", "september",
        "oct", "october", "nov", "november", "dec", "december"
    ]

    private static func containsMonthName(_ lowerPhrase: String) -> Bool {
        let words = lowerPhrase.split { !$0.isLetter }.map(String.init)
        return words.contains { monthNames.contains($0) }
    }

    private static let weekdayTokens: Set<String> = [
        "monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday",
        "mon", "tue", "tues", "wed", "thu", "thur", "thurs", "fri", "sat", "sun"
    ]

    private static func containsUnsupportedDateToken(_ lowerPhrase: String) -> Bool {
        let words = lowerPhrase.split { !$0.isLetter && !$0.isNumber }
        if words.contains(where: { weekdayTokens.contains(String($0)) }) {
            return true
        }

        let characters = Array(lowerPhrase)
        for index in characters.indices.dropFirst().dropLast()
        where characters[index] == "/" || characters[index] == "-" {
            if characters[index - 1].isNumber, characters[index + 1].isNumber {
                return true
            }
        }
        return false
    }

    private static func relativeDayOffset(in lowerPhrase: String) -> Int? {
        let words = Set(lowerPhrase.split { !$0.isLetter }.map(String.init))
        if words.contains("tomorrow") {
            return 1
        }
        if words.contains("yesterday") {
            return -1
        }
        if words.contains("today") || words.contains("tonight") {
            return 0
        }
        return nil
    }

    // MARK: - Formatting

    private static func formatSourceDescription(instant: Date, zone: TimeZone) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = zone
        formatter.dateFormat = "EEEE, d MMMM, h:mm a"
        return "\(formatter.string(from: instant)), \(gmtOffsetString(for: zone, instant: instant))"
    }

    private static func formatLocalDescription(instant: Date, zone: TimeZone) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = zone
        formatter.dateFormat = "MMMM d, yyyy 'at' HH:mm"
        return formatter.string(from: instant)
    }

    private static func gmtOffsetString(for zone: TimeZone, instant: Date) -> String {
        let hours = zone.secondsFromGMT(for: instant) / 3600
        return hours >= 0 ? "GMT+\(hours)" : "GMT\(hours)"
    }
}

public final class TimeProvider: ResultProvider {
    public let id: ProviderID = .time
    private let now: @Sendable () -> Date
    private let localTimeZone: @Sendable () -> TimeZone

    public init(
        now: @escaping @Sendable () -> Date = Date.init,
        localTimeZone: @escaping @Sendable () -> TimeZone = { TimeZone.current }
    ) {
        self.now = now
        self.localTimeZone = localTimeZone
    }

    public func results(for query: ParsedQuery) async throws -> [SearchResult] {
        guard query.mode == .general else {
            return []
        }
        guard let conversion = TimeQueryParser.parse(query.term, now: now(), localZone: localTimeZone()) else {
            return []
        }

        let hero = HeroContent(
            left: conversion.sourceDescription,
            leftBadge: Self.gmtBadge(from: conversion.sourceDescription),
            right: conversion.localDescription,
            rightBadge: "Your Time"
        )
        return [
            SearchResult(
                id: "time",
                providerID: .time,
                title: conversion.localDescription,
                icon: .symbol("clock"),
                // Preserve the raw term so Ranker's exact/prefix tiers still find
                // this result — same trick as CalculatorProvider/CurrencyProvider.
                keywords: [query.term],
                action: .copyText(conversion.localDescription),
                hero: hero,
                sortHint: 0
            )
        ]
    }

    private nonisolated static func gmtBadge(from sourceDescription: String) -> String? {
        guard let range = sourceDescription.range(of: ", GMT", options: .backwards) else {
            return nil
        }
        let start = sourceDescription.index(range.lowerBound, offsetBy: 2)
        return String(sourceDescription[start...])
    }
}
