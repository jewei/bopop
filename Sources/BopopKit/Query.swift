import Foundation

public nonisolated enum Mode: String, Hashable, Sendable {
    case general
    case apps
    case fileSearch
    case clipboard
    case emoji
    case translation
    case snippets
}

public nonisolated struct ParsedQuery: Equatable, Sendable {
    public let mode: Mode
    public let term: String

    public init(mode: Mode, term: String) {
        self.mode = mode
        self.term = term
    }
}

public nonisolated enum QueryParser {
    public static func parse(raw: String, stickyMode: Mode) -> ParsedQuery {
        guard stickyMode == .general else {
            return ParsedQuery(mode: stickyMode, term: raw)
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
        if prefix.caseInsensitiveCompare("f ") == .orderedSame {
            return ParsedQuery(
                mode: .fileSearch,
                term: raw[prefixEnd...].trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }
        if prefix.caseInsensitiveCompare("t ") == .orderedSame {
            return ParsedQuery(
                mode: .translation,
                term: raw[prefixEnd...].trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }

        return ParsedQuery(
            mode: .general,
            term: raw.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }
}

public nonisolated enum EscapeAction: Equatable, Sendable {
    case clearText
    case exitMode
    case closePanel
}

public nonisolated enum EscapePolicy {
    public static func action(textIsEmpty: Bool, stickyMode: Mode) -> EscapeAction {
        if !textIsEmpty {
            return .clearText
        }
        if stickyMode != .general {
            return .exitMode
        }
        return .closePanel
    }
}
