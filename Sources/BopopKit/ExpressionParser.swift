import Foundation

public nonisolated enum ExpressionParser {
    public enum ParseError: Error, Equatable {
        case empty
        case unexpectedCharacter(Character)
        case unexpectedEnd
        case unbalancedParenthesis
        case trailingGarbage
        case divisionByZero
        case notFinite
    }

    public static func evaluate(_ input: String) throws -> Double {
        guard input.contains(where: { !$0.isWhitespace }) else {
            throw ParseError.empty
        }

        let tokens = try tokenize(input)
        var parser = Parser(tokens: tokens)
        return try parser.parse()
    }

    private static func tokenize(_ input: String) throws -> [Token] {
        let characters = input.map(normalize)
        var tokens: [Token] = []
        var index = characters.startIndex

        while index < characters.endIndex {
            let character = characters[index]
            if character.isWhitespace {
                index += 1
                continue
            }

            if isDigit(character) || character == "." {
                let start = index
                var hasDigit = false
                var hasDecimalPoint = false

                while index < characters.endIndex {
                    let numberCharacter = characters[index]
                    if isDigit(numberCharacter) {
                        hasDigit = true
                        index += 1
                    } else if numberCharacter == ".", !hasDecimalPoint {
                        hasDecimalPoint = true
                        index += 1
                    } else {
                        break
                    }
                }

                guard hasDigit else {
                    throw ParseError.unexpectedCharacter(character)
                }
                let literal = String(characters[start..<index])
                guard let value = Double(literal) else {
                    throw ParseError.unexpectedCharacter(character)
                }
                guard value.isFinite else {
                    throw ParseError.notFinite
                }
                tokens.append(.number(value))
                continue
            }

            if character.isLetter {
                let start = index
                while index < characters.endIndex, characters[index].isLetter {
                    index += 1
                }
                let identifier = String(characters[start..<index]).lowercased()
                switch identifier {
                case "pi":
                    tokens.append(.number(.pi))
                case "e":
                    tokens.append(.number(M_E))
                default:
                    throw ParseError.unexpectedCharacter(characters[start])
                }
                continue
            }

            switch character {
            case "+": tokens.append(.plus)
            case "-": tokens.append(.minus)
            case "*": tokens.append(.multiply)
            case "/": tokens.append(.divide)
            case "%": tokens.append(.remainder)
            case "^": tokens.append(.power)
            case "(": tokens.append(.leftParenthesis)
            case ")": tokens.append(.rightParenthesis)
            default: throw ParseError.unexpectedCharacter(character)
            }
            index += 1
        }

        return tokens
    }

    private static func normalize(_ character: Character) -> Character {
        switch character {
        case "×": "*"
        case "÷": "/"
        case "−", "–": "-"
        default: character
        }
    }

    private static func isDigit(_ character: Character) -> Bool {
        "0123456789".contains(character)
    }

    private enum Token: Equatable {
        case number(Double)
        case plus
        case minus
        case multiply
        case divide
        case remainder
        case power
        case leftParenthesis
        case rightParenthesis
    }

    private struct Parser {
        let tokens: [Token]
        var index = 0

        mutating func parse() throws -> Double {
            let value = try expression()
            guard index == tokens.endIndex else {
                throw ParseError.trailingGarbage
            }
            return try finite(value)
        }

        private mutating func expression() throws -> Double {
            var value = try term()
            while let token = current, token == .plus || token == .minus {
                index += 1
                let right = try term()
                value = try finite(token == .plus ? value + right : value - right)
            }
            return value
        }

        private mutating func term() throws -> Double {
            var value = try factor()
            while let token = current,
                  token == .multiply || token == .divide || token == .remainder {
                index += 1
                let right = try factor()
                switch token {
                case .multiply:
                    value = try finite(value * right)
                case .divide:
                    guard right != 0 else {
                        throw ParseError.divisionByZero
                    }
                    value = try finite(value / right)
                case .remainder:
                    guard right != 0 else {
                        throw ParseError.divisionByZero
                    }
                    value = try finite(value.truncatingRemainder(dividingBy: right))
                default:
                    break
                }
            }
            return value
        }

        private mutating func factor() throws -> Double {
            if current == .minus {
                index += 1
                return try finite(-(try factor()))
            }
            return try power()
        }

        private mutating func power() throws -> Double {
            let base = try primary()
            guard current == .power else {
                return base
            }

            index += 1
            let exponent = try factor()
            return try finite(pow(base, exponent))
        }

        private mutating func primary() throws -> Double {
            guard let token = current else {
                throw ParseError.unexpectedEnd
            }

            switch token {
            case let .number(value):
                index += 1
                return value
            case .leftParenthesis:
                index += 1
                let value = try expression()
                guard current == .rightParenthesis else {
                    throw ParseError.unbalancedParenthesis
                }
                index += 1
                return value
            default:
                throw ParseError.trailingGarbage
            }
        }

        private var current: Token? {
            index < tokens.endIndex ? tokens[index] : nil
        }

        private func finite(_ value: Double) throws -> Double {
            guard value.isFinite else {
                throw ParseError.notFinite
            }
            return value
        }
    }
}
