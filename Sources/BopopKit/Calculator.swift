import Foundation

public enum CalculatorFormatter {
    private static let posixLocale = Locale(identifier: "en_US_POSIX")

    public static func string(from value: Double) -> String {
        if value == 0 {
            return "0"
        }

        if value.rounded(.towardZero) == value, abs(value) < 1e15 {
            return String(format: "%.0f", locale: posixLocale, value)
        }

        var formatted = String(format: "%.10f", locale: posixLocale, value)
        while formatted.last == "0" {
            formatted.removeLast()
        }
        if formatted.last == "." {
            formatted.removeLast()
        }
        // Ten decimal places round every magnitude below 5e-11 to all zeros,
        // which reported a nonzero answer as a flat "0" — and that "0" is
        // also the copy payload and the ⇥ autocomplete text. Fall back to
        // significant-digit notation instead of lying about the value.
        guard formatted != "0", formatted != "-0" else {
            return String(format: "%g", locale: posixLocale, value)
        }
        return formatted
    }

    /// Built once and locked rather than constructed per call: this runs on
    /// every keystroke of a calculator query, the same hot path that made
    /// CurrencyProvider hoist its own formatters. NumberFormatter is not
    /// thread-safe and providers now run off the main actor, so `FormatterBox`
    /// supplies the serialization the actor used to.
    private static let groupingFormatter: FormatterBox<NumberFormatter> = {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = true
        formatter.maximumFractionDigits = 10
        return FormatterBox(formatter)
    }()

    public static func grouped(from value: Double) -> String {
        guard value != 0 else {
            return "0"
        }
        let formatted = groupingFormatter.withLock {
            $0.string(from: NSNumber(value: value))
        }
        // Same all-zeros trap as above: maximumFractionDigits 10 renders
        // ±4e-11 as "0"/"-0". `string(from:)` has the significant-digit
        // fallback for magnitudes this can't represent.
        guard let formatted, formatted != "0", formatted != "-0" else {
            return string(from: value)
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
        let heroLeft = expression.trimmingCharacters(in: .whitespacesAndNewlines)
        let hero = HeroContent(
            left: heroLeft,
            leftBadge: Self.operationBadge(heroLeft),
            right: CalculatorFormatter.grouped(from: value),
            rightBadge: Self.spellOutBadge(value),
            autocompleteText: formatted
        )
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
                hero: hero,
                sortHint: 0
            )
        ]
    }

    private static func operationBadge(_ expression: String) -> String? {
        var depth = 0
        var categories: Set<String> = []
        var previousSignificant: Character?

        for character in expression {
            if character == "(" {
                depth += 1
                previousSignificant = character
                continue
            }
            if character == ")" {
                depth -= 1
                previousSignificant = character
                continue
            }
            if character.isWhitespace {
                continue
            }
            if depth == 0, let category = operatorCategory(character) {
                let isMinus = character == "-" || character == "−" || character == "–"
                let isUnary = isMinus
                    && !(previousSignificant?.isNumber == true || previousSignificant == ")")
                if !isUnary {
                    categories.insert(category)
                }
            }
            previousSignificant = character
        }

        return categories.count == 1 ? categories.first : nil
    }

    private static func operatorCategory(_ character: Character) -> String? {
        switch character {
        case "*", "×": return "Product"
        case "+": return "Sum"
        case "-", "−", "–": return "Difference"
        case "/", "÷": return "Quotient"
        case "%": return "Remainder"
        case "^": return "Power"
        default: return nil
        }
    }

    /// Hoisted for the same reason as `CalculatorFormatter.groupingFormatter`
    /// — and more so here, since `.spellOut` is the most expensive style to
    /// construct and this ran once per keystroke.
    private static let spellOutFormatter: FormatterBox<NumberFormatter> = {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US")
        formatter.numberStyle = .spellOut
        return FormatterBox(formatter)
    }()

    private static func spellOutBadge(_ value: Double) -> String? {
        guard value.rounded(.towardZero) == value, abs(value) < 1e9 else {
            return nil
        }

        guard let spelled = spellOutFormatter.withLock({
            $0.string(from: NSNumber(value: value))
        }) else {
            return nil
        }
        return spelled.capitalized
    }

    public static func isCandidate(_ term: String) -> Bool {
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
