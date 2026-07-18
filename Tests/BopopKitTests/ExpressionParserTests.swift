import Foundation
import Testing
@testable import BopopKit

@Test(arguments: [
    ("2+2", 4.0, 1e-12),
    ("2*(3+4)^2", 98.0, 1e-12),
    ("-3^2", -9.0, 1e-12),
    ("(-3)^2", 9.0, 1e-12),
    ("2^3^2", 512.0, 1e-12),
    ("2^-3", 0.125, 1e-12),
    ("10%3", 1.0, 1e-12),
    ("10.5%3", 1.5, 1e-12),
    (".5+.5", 1.0, 1e-12),
    ("2.", 2.0, 1e-12),
    ("pi", 3.14159265, 1e-8),
    ("2*pi*e", 17.0794684, 1e-7),
    ("6×2", 12.0, 1e-12),
    ("8÷2", 4.0, 1e-12),
    ("5−2", 3.0, 1e-12),
    ("5–2", 3.0, 1e-12),
    (" 2 + 2 ", 4.0, 1e-12),
    ("((2+3)*(4-1))", 15.0, 1e-12)
])
func expressionParserEvaluates(
    input: String,
    expected: Double,
    accuracy: Double
) throws {
    let value = try ExpressionParser.evaluate(input)
    #expect(abs(value - expected) <= accuracy)
}

@Test(arguments: [
    ("", ExpressionParser.ParseError.empty),
    ("2+", ExpressionParser.ParseError.unexpectedEnd),
    ("(2+3", ExpressionParser.ParseError.unbalancedParenthesis),
    ("2+3)", ExpressionParser.ParseError.trailingGarbage),
    ("1/0", ExpressionParser.ParseError.divisionByZero),
    ("5%0", ExpressionParser.ParseError.divisionByZero),
    ("10^400", ExpressionParser.ParseError.notFinite),
    ("2$3", ExpressionParser.ParseError.unexpectedCharacter("$")),
    ("pie+1", ExpressionParser.ParseError.unexpectedCharacter("p"))
])
func expressionParserRejects(
    input: String,
    expected: ExpressionParser.ParseError
) {
    #expect(throws: expected) {
        try ExpressionParser.evaluate(input)
    }
}
