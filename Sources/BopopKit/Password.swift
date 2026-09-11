import Foundation
import Security

/// Which character classes a generated password may draw from.
public struct PasswordAlphabet: OptionSet, Hashable, Sendable {
    public let rawValue: Int

    public init(rawValue: Int) {
        self.rawValue = rawValue
    }

    public static let lowercase = PasswordAlphabet(rawValue: 1 << 0)
    public static let uppercase = PasswordAlphabet(rawValue: 1 << 1)
    public static let digits = PasswordAlphabet(rawValue: 1 << 2)
    public static let symbols = PasswordAlphabet(rawValue: 1 << 3)

    public static let letters: PasswordAlphabet = [.lowercase, .uppercase]
    public static let alphanumeric: PasswordAlphabet = [.letters, .digits]
    public static let everything: PasswordAlphabet = [.alphanumeric, .symbols]

    /// Punctuation that survives a round trip through a shell argument, a CSV
    /// cell and a URL query without needing escapes. Quotes, backslash,
    /// backtick, pipe, slash and tilde are left out for that reason alone —
    /// they cost a few bits of pool size and buy a lot of paste-it-anywhere.
    static let symbolCharacters = Array("!@#$%^&*()-_=+[]{};:,.?")

    /// One array per selected class. Kept split rather than flattened because
    /// `PasswordGenerator` seeds one character from each class before filling
    /// the rest — a password that promises symbols and happens to contain none
    /// fails the form it was generated for.
    var pools: [[Character]] {
        let classes: [(PasswordAlphabet, [Character])] = [
            (.lowercase, Array("abcdefghijklmnopqrstuvwxyz")),
            (.uppercase, Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ")),
            (.digits, Array("0123456789")),
            (.symbols, Self.symbolCharacters)
        ]
        return classes.compactMap { member, characters in
            contains(member) ? characters : nil
        }
    }

    /// Badge copy for the hero card: "a–z · A–Z · 0–9 · !@#".
    var description: String {
        var pieces: [String] = []
        if contains(.lowercase) {
            pieces.append("a–z")
        }
        if contains(.uppercase) {
            pieces.append("A–Z")
        }
        if contains(.digits) {
            pieces.append("0–9")
        }
        if contains(.symbols) {
            pieces.append("!@#")
        }
        return pieces.joined(separator: " · ")
    }
}

/// The word list behind the passphrase recipe.
///
/// BIP-39's English list, vendored at `Resources/wordlist.txt`: 2048 unique
/// words, MIT-licensed like Bopop itself, no word longer than eight letters,
/// and every word identified by its first four letters — which is what makes a
/// passphrase readable off a screen and retypable without a second look.
///
/// 2048 is a power of two on purpose: each word contributes exactly 11 bits, so
/// the strength figure needs no rounding apology.
public enum PassphraseWords {
    public static let expectedCount = 2048
    public static let bitsPerWord = 11

    /// Loaded once, off any actor. 13 KB and 2048 short strings, so there is
    /// nothing here worth the asynchronous warm-up `EmojiCatalog` needs for its
    /// 174 KB of JSON.
    public static let all: [String] = {
        guard let url = resourceURL(),
              let text = try? String(contentsOf: url, encoding: .utf8) else {
            return []
        }
        return text.split(whereSeparator: \.isNewline).map(String.init)
    }()

    /// Distributed apps copy the list into the conventional app Resources
    /// directory; SwiftPM build products keep their generated module bundle.
    /// Same two-step lookup as the emoji catalog, for the same reason.
    private static func resourceURL() -> URL? {
        Bundle.main.url(forResource: "wordlist", withExtension: "txt")
            ?? Bundle.module.url(forResource: "wordlist", withExtension: "txt")
    }
}

/// What to generate. Two shapes, because "twenty characters" and "five words"
/// are not the same unit and pretending otherwise is how a passphrase ends up
/// reporting its length in the wrong one.
public enum PasswordRecipe: Equatable, Sendable {
    case characters(length: Int, alphabet: PasswordAlphabet)
    case words(count: Int, separator: Character)

    /// Row subtitle and hero left pane: "20 characters", "5 words".
    public var sizeDescription: String {
        switch self {
        case let .characters(length, _):
            return "\(length) \(length == 1 ? "character" : "characters")"
        case let .words(count, _):
            return "\(count) \(count == 1 ? "word" : "words")"
        }
    }

    /// Hero badge: what the recipe drew from.
    public var poolDescription: String {
        switch self {
        case let .characters(_, alphabet):
            return alphabet.description
        case .words:
            return "from \(PassphraseWords.expectedCount) words"
        }
    }
}

/// How much guessing a recipe costs an attacker, and a word for it.
///
/// For character recipes `bits` is the pool-size estimate —
/// `length × log2(poolSize)` — which is the figure every password tool quotes.
/// Seeding one character per class makes the true value very slightly lower, so
/// treat it as an upper bound; the gap is a fraction of a bit at these lengths
/// and never crosses a label boundary. For word recipes the figure is exact:
/// 11 bits per word, from a list of exactly 2048.
public struct PasswordStrength: Equatable, Sendable {
    public let bits: Int
    public let label: String

    public init(recipe: PasswordRecipe) {
        switch recipe {
        case let .characters(length, alphabet):
            let poolSize = alphabet.pools.reduce(0) { $0 + $1.count }
            guard poolSize > 1, length > 0 else {
                bits = 0
                label = Self.label(for: 0)
                return
            }
            bits = Int((Double(length) * log2(Double(poolSize))).rounded(.down))
        case let .words(count, _):
            bits = max(0, count) * PassphraseWords.bitsPerWord
        }
        label = Self.label(for: bits)
    }

    private static func label(for bits: Int) -> String {
        switch bits {
        case ..<45: "Weak"
        case ..<65: "Fair"
        case ..<90: "Strong"
        default: "Very strong"
        }
    }

    /// "128 bits · Very strong" — the hero badge and the row subtitle.
    public var summary: String {
        "\(bits) bits · \(label)"
    }
}

/// Where random bits come from, behind one closure so tests can supply a
/// deterministic sequence without the generator itself knowing about testing.
public typealias RandomWordSource = @Sendable () -> UInt64

public enum PasswordGenerator {
    /// `SystemRandomNumberGenerator` is documented as cryptographically secure
    /// "whenever possible" — a hedge that is fine for shuffling a playlist and
    /// not fine for the value this function returns. `SecRandomCopyBytes`
    /// carries no such qualifier, so it is what production draws from.
    public static let secureRandomWord: RandomWordSource = {
        var value: UInt64 = 0
        let status = withUnsafeMutableBytes(of: &value) { buffer in
            SecRandomCopyBytes(kSecRandomDefault, buffer.count, buffer.baseAddress!)
        }
        guard status == errSecSuccess else {
            // Documented as effectively never failing on Darwin. If it somehow
            // does, `arc4random_buf` — what SystemRandomNumberGenerator uses
            // here — draws from the same kernel pool and cannot report
            // failure, which beats both crashing the launcher and the far
            // worse alternative of returning the still-zeroed `value`.
            var fallback = SystemRandomNumberGenerator()
            return fallback.next()
        }
        return value
    }

    public static func generate(
        _ recipe: PasswordRecipe,
        randomWord: @escaping RandomWordSource = secureRandomWord
    ) -> String {
        var generator = SourcedRandomNumberGenerator(source: randomWord)
        return generate(recipe, using: &generator)
    }

    public static func generate<Generator: RandomNumberGenerator>(
        _ recipe: PasswordRecipe,
        using generator: inout Generator
    ) -> String {
        switch recipe {
        case let .characters(length, alphabet):
            return characters(length: length, alphabet: alphabet, using: &generator)
        case let .words(count, separator):
            return words(count: count, separator: separator, using: &generator)
        }
    }

    /// Guarantees one character from every selected class, then fills the rest
    /// from the union and shuffles — so position tells an attacker nothing
    /// about which class seeded it.
    private static func characters<Generator: RandomNumberGenerator>(
        length: Int,
        alphabet: PasswordAlphabet,
        using generator: inout Generator
    ) -> String {
        let pools = alphabet.pools
        guard length > 0, !pools.isEmpty else {
            return ""
        }

        var characters: [Character] = []
        characters.reserveCapacity(length)
        // `prefix` matters when the recipe asks for fewer characters than it
        // has classes: seeding all four into a 3-character password would
        // overrun the requested length.
        for pool in pools.prefix(length) {
            characters.append(pool.randomElement(using: &generator)!)
        }
        let combined = pools.flatMap { $0 }
        while characters.count < length {
            characters.append(combined.randomElement(using: &generator)!)
        }
        characters.shuffle(using: &generator)
        return String(characters)
    }

    /// Words are drawn independently and with replacement. A repeat is allowed
    /// on purpose: refusing one would make the phrase a selection without
    /// replacement, which lowers the entropy the 11-bits-per-word figure
    /// claims — and the figure is what the row shows the user.
    private static func words<Generator: RandomNumberGenerator>(
        count: Int,
        separator: Character,
        using generator: inout Generator
    ) -> String {
        let vocabulary = PassphraseWords.all
        guard count > 0, !vocabulary.isEmpty else {
            return ""
        }
        return (0..<count)
            .map { _ in vocabulary.randomElement(using: &generator)! }
            .joined(separator: String(separator))
    }
}

/// Adapts a `RandomWordSource` closure to the stdlib's generator protocol.
/// `next()` is deliberately non-mutating: the closure owns whatever state
/// exists, so copying this struct never forks a random stream.
struct SourcedRandomNumberGenerator: RandomNumberGenerator {
    let source: RandomWordSource

    func next() -> UInt64 {
        source()
    }
}

public struct PasswordRequest: Equatable, Sendable {
    public let length: Int
    /// True when the user typed a length ("password 32"). The provider needs
    /// to know, because that term matches none of the trigger vocabulary and
    /// has to be added to the row keywords for Ranker to keep the rows.
    public let lengthWasSpecified: Bool

    public init(length: Int, lengthWasSpecified: Bool) {
        self.length = length
        self.lengthWasSpecified = lengthWasSpecified
    }
}

public enum PasswordQuery {
    public static let defaultLength = 20
    /// The upper bound is a display guarantee, not a cryptographic one. 64
    /// characters of the full alphabet is already 410 bits; what decides the
    /// number is that the hero card can render 64 characters in full at its
    /// smallest font, and 96 cannot. Raising this re-introduces a card that
    /// shows a shorter password than the one ⏎ copies —
    /// `heroCardShowsEveryGeneratablePasswordInFull` fails if it is raised.
    public static let lengthLimits = 6...64
    /// A 32-digit PIN is not a PIN. Explicit lengths still shorten it.
    public static let pinLengthLimit = 12
    /// Five words is 55 bits. Four would be 44, which this file's own labels
    /// call Weak — not a default to ship.
    public static let passphraseWordLimits = 5...20
    public static let passphraseSeparator: Character = "-"

    /// Typing one of these as the first word asks for a password.
    ///
    /// `pass` is a trigger but deliberately absent from `keywords` below: it is
    /// a prefix of Apple's own Passwords app, and an exact-tier match on it
    /// would push that app off its own name. As a trigger only, these rows
    /// appear on "pass" at prefix tier — just below the app, where they belong.
    public static let triggers: Set<String> = [
        "password", "passwords", "pass", "pw", "pwd", "pwgen", "passgen",
        "passphrase"
    ]

    /// What Ranker scores the query against. It sees only `title` and
    /// `keywords`, and the title of these rows is the password itself, so the
    /// whole vocabulary has to be spelled out here.
    public static let keywords = [
        "password", "passwords", "pw", "pwd", "pwgen", "passgen",
        "passphrase", "generate password", "random password"
    ]

    public static func request(from term: String) -> PasswordRequest? {
        let fields = term.split(whereSeparator: \.isWhitespace)
        guard let head = fields.first,
              triggers.contains(head.lowercased()) else {
            return nil
        }
        guard fields.count > 1 else {
            return PasswordRequest(length: defaultLength, lengthWasSpecified: false)
        }
        // Anything past a length is not a password request — "pass the salt"
        // should search the web, not silently generate a secret.
        guard fields.count == 2 else {
            return nil
        }
        let digits = fields[1]
        guard !digits.isEmpty, digits.allSatisfy({ $0.isASCII && $0.isNumber }) else {
            return nil
        }
        // A number too large for Int is still a request for "as long as
        // possible", so clamp rather than refuse.
        let requested = Int(digits) ?? lengthLimits.upperBound
        return PasswordRequest(
            length: min(max(requested, lengthLimits.lowerBound), lengthLimits.upperBound),
            lengthWasSpecified: true
        )
    }

    /// The requested length is in characters, and a word count has to come out
    /// of it. Six is the measured cost of one word in this list — 5.4 letters
    /// plus a separator — so this is "enough words to fill the length asked
    /// for", floored at a word count that is not weak.
    public static func wordCount(forLength length: Int) -> Int {
        let needed = (max(0, length) + 5) / 6
        return min(max(needed, passphraseWordLimits.lowerBound), passphraseWordLimits.upperBound)
    }
}

/// One offered recipe, with the stable id that identifies it in usage history.
public struct PasswordVariant: Equatable, Sendable {
    public let id: String
    public let name: String
    public let recipe: PasswordRecipe

    /// The rows a request produces, in display order. Frecency can promote a
    /// variant above this order — whichever ends up first becomes the hero —
    /// which is the point: the recipe you keep choosing rises to ⏎.
    public static func catalog(for request: PasswordRequest) -> [PasswordVariant] {
        let length = request.length
        return [
            PasswordVariant(
                id: "strong",
                name: "Strong",
                recipe: .characters(length: length, alphabet: .everything)
            ),
            PasswordVariant(
                id: "alphanumeric",
                name: "Letters & digits",
                recipe: .characters(length: length, alphabet: .alphanumeric)
            ),
            PasswordVariant(
                id: "passphrase",
                name: "Passphrase",
                recipe: .words(
                    count: PasswordQuery.wordCount(forLength: length),
                    separator: PasswordQuery.passphraseSeparator
                )
            ),
            PasswordVariant(
                id: "pin",
                name: "PIN",
                recipe: .characters(
                    length: min(
                        request.lengthWasSpecified ? length : PasswordQuery.lengthLimits.lowerBound,
                        PasswordQuery.pinLengthLimit
                    ),
                    alphabet: .digits
                )
            )
        ]
    }
}

public final class PasswordProvider: ResultProvider {
    public let id: ProviderID = .password

    private let randomWord: RandomWordSource

    public init(randomWord: @escaping RandomWordSource = PasswordGenerator.secureRandomWord) {
        self.randomWord = randomWord
    }

    public func results(for query: ParsedQuery) async throws -> [SearchResult] {
        guard query.mode == .general,
              let request = PasswordQuery.request(from: query.term) else {
            return []
        }

        var keywords = PasswordQuery.keywords
        if request.lengthWasSpecified {
            keywords.append(query.term)
        }

        return PasswordVariant.catalog(for: request).enumerated().compactMap { index, variant in
            let password = PasswordGenerator.generate(variant.recipe, randomWord: randomWord)
            // A missing or unreadable word list empties the vocabulary. Drop
            // the row rather than offer an empty one that copies nothing.
            guard !password.isEmpty else {
                return nil
            }
            let strength = PasswordStrength(recipe: variant.recipe)
            return SearchResult(
                // Names the recipe, never the password. `UsageStore` writes
                // this id to disk on every ⏎, and a generated secret has no
                // business in a frecency file.
                id: "password:\(variant.id)",
                providerID: .password,
                title: password,
                subtitle: "\(variant.recipe.sizeDescription) · \(strength.summary)",
                icon: .symbol("key.fill"),
                keywords: keywords,
                badge: variant.name,
                action: .copySecret(password),
                hero: HeroContent(
                    left: variant.recipe.sizeDescription,
                    leftBadge: variant.recipe.poolDescription,
                    right: password,
                    rightBadge: strength.summary,
                    note: "Kept out of history",
                    // A password is a payload, not prose. See
                    // `HeroContent.rightWrapsByCharacter`.
                    rightWrapsByCharacter: true
                ),
                sortHint: index
            )
        }
    }
}
