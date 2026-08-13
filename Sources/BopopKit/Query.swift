import Foundation

public enum Mode: String, CaseIterable, Hashable, Sendable {
    case general
    case apps
    case fileSearch
    case clipboard
    case emoji
    case translation
    case snippets
}

public struct ParsedQuery: Equatable, Sendable {
    public let mode: Mode
    public let term: String

    public init(mode: Mode, term: String) {
        self.mode = mode
        self.term = term
    }
}

public enum QueryParser {
    /// Two-character mode prefixes (`"f "`, `"t "`, …), each followed by a
    /// space, checked case-insensitively against `raw`'s first two
    /// characters. The `:` emoji prefix stays a separate branch below — it's
    /// a different shape (one character, no trailing space, minimum-length
    /// rule of its own) rather than another row in this table.
    private static let prefixModes: [(prefix: String, mode: Mode)] = [
        ("f ", .fileSearch),
        ("t ", .translation)
    ]

    public static func parse(raw: String, stickyMode: Mode) -> ParsedQuery {
        guard stickyMode == .general else {
            // Trimmed exactly like every general-mode branch below. Ranker
            // folds case and diacritics but never trims, so an untrimmed term
            // made a single trailing space tier-mismatch every candidate and
            // blank the whole list — mid-word, while the user was still typing.
            return ParsedQuery(
                mode: stickyMode,
                term: raw.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }

        if raw.first == ":", raw.count > 1 {
            return ParsedQuery(
                mode: .emoji,
                term: String(raw.dropFirst()).trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }

        guard raw.count >= 2 else {
            return ParsedQuery(
                mode: .general,
                term: raw.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }

        let prefixEnd = raw.index(raw.startIndex, offsetBy: 2)
        let prefix = raw[..<prefixEnd]
        for entry in prefixModes
        where prefix.caseInsensitiveCompare(entry.prefix) == .orderedSame {
            return ParsedQuery(
                mode: entry.mode,
                term: raw[prefixEnd...].trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }

        return ParsedQuery(
            mode: .general,
            term: raw.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }
}
