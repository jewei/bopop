import Foundation

public nonisolated enum CalculatorFormatter {
    public static func string(from value: Double) -> String {
        if value == 0 {
            return "0"
        }

        let locale = Locale(identifier: "en_US_POSIX")
        if value.rounded(.towardZero) == value, abs(value) < 1e15 {
            return String(format: "%.0f", locale: locale, value)
        }

        var formatted = String(format: "%.10f", locale: locale, value)
        while formatted.last == "0" {
            formatted.removeLast()
        }
        if formatted.last == "." {
            formatted.removeLast()
        }
        return formatted
    }
}

public final class CalculatorProvider: ResultProvider {
    public let id: ProviderID = .calculator

    public init() {}

    public func results(for query: ParsedQuery) async throws -> [SearchResult] {
        guard query.mode == .general, Self.isCandidate(query.term) else {
            return []
        }

        let trimmedTerm = query.term.trimmingCharacters(in: .whitespacesAndNewlines)
        let expression = trimmedTerm.first == "="
            ? String(trimmedTerm.dropFirst())
            : trimmedTerm
        guard let value = try? ExpressionParser.evaluate(expression) else {
            return []
        }

        let formatted = CalculatorFormatter.string(from: value)
        return [
            SearchResult(
                id: "calc",
                providerID: .calculator,
                title: "= \(formatted)",
                icon: .symbol("equal.circle"),
                // The title does not match the expression. Preserve the raw term so
                // Ranker gives this result an exact tier instead of filtering it out.
                keywords: [query.term],
                action: .copyText(formatted),
                secondaryActions: [.copyText(formatted)],
                sortHint: 0
            )
        ]
    }

    public nonisolated static func isCandidate(_ term: String) -> Bool {
        let trimmed = term.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return false
        }
        if trimmed.first == "=" {
            return true
        }

        let characters = Array(trimmed)
        var index = characters.startIndex
        var hasDigit = false
        var hasOperator = false

        while index < characters.endIndex {
            let character = characters[index]
            if character.isWhitespace || character == "."
                || character == "(" || character == ")" {
                index += 1
                continue
            }
            if "0123456789".contains(character) {
                hasDigit = true
                index += 1
                continue
            }
            if "+-*/%^×÷−–".contains(character) {
                hasOperator = true
                index += 1
                continue
            }
            if character.isLetter {
                let start = index
                while index < characters.endIndex, characters[index].isLetter {
                    index += 1
                }
                let identifier = String(characters[start..<index]).lowercased()
                guard identifier == "pi" || identifier == "e" else {
                    return false
                }
                continue
            }
            return false
        }

        return hasDigit && hasOperator
    }
}
