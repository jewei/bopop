import Foundation
import Testing
@testable import BopopKit

/// A deterministic stand-in for the secure source.
///
/// It has to produce a *varied* sequence, not a constant: the stdlib's
/// `next(upperBound:)` rejection-samples, so a source that always answered the
/// same word would spin forever rather than fail a test. splitmix64 is three
/// lines and passes that bar.
private final class SeededWords: @unchecked Sendable {
    private let lock = NSLock()
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    var source: RandomWordSource {
        { [self] in
            lock.lock()
            defer { lock.unlock() }
            state &+= 0x9E37_79B9_7F4A_7C15
            var word = state
            word = (word ^ (word >> 30)) &* 0xBF58_476D_1CE4_E5B9
            word = (word ^ (word >> 27)) &* 0x94D0_49BB_1331_11EB
            return word ^ (word >> 31)
        }
    }
}

/// Returns rising multiples of `step`, so every draw lands on the same index
/// of a `step`-sized collection.
private final class SteppingWords: @unchecked Sendable {
    private let lock = NSLock()
    private let step: UInt64
    private var value: UInt64 = 0

    init(step: UInt64) {
        self.step = step
    }

    var source: RandomWordSource {
        { [self] in
            lock.lock()
            defer { lock.unlock() }
            value &+= step
            return value
        }
    }
}

// MARK: - Query parsing

@Test func passwordQueryRecognisesItsTriggers() {
    for trigger in [
        "password", "passwords", "pass", "pw", "pwd", "pwgen", "passgen",
        "passphrase", "PassWord"
    ] {
        let request = PasswordQuery.request(from: trigger)
        #expect(request?.length == PasswordQuery.defaultLength, "\(trigger) should trigger")
        #expect(request?.lengthWasSpecified == false)
    }
}

@Test func passwordQueryIgnoresEverythingElse() {
    for term in [
        "passport",          // a trigger must be the whole first word
        "passenger",
        "my password",       // …and the first word
        "pass the salt",     // a sentence is not a length
        "password abc",      // neither is a word
        "password 12 34",
        "password -8",
        "",
        "p"
    ] {
        #expect(PasswordQuery.request(from: term) == nil, "\(term) should not trigger")
    }
}

@Test func passwordQueryReadsAndClampsAnExplicitLength() {
    #expect(PasswordQuery.request(from: "password 32")?.length == 32)
    #expect(PasswordQuery.request(from: "pw 8")?.lengthWasSpecified == true)
    #expect(PasswordQuery.request(from: "password 1")?.length == PasswordQuery.lengthLimits.lowerBound)
    #expect(PasswordQuery.request(from: "password 9000")?.length == PasswordQuery.lengthLimits.upperBound)
    // Too large for Int is still "as long as possible", not a refusal.
    #expect(
        PasswordQuery.request(from: "password 99999999999999999999")?.length
            == PasswordQuery.lengthLimits.upperBound
    )
}

/// The floor is the load-bearing part: four words is 44 bits, which this
/// file's own labels call Weak.
@Test func wordCountFillsTheRequestedLengthWithoutGoingWeak() {
    #expect(PasswordQuery.wordCount(forLength: 6) == 5)
    #expect(PasswordQuery.wordCount(forLength: PasswordQuery.defaultLength) == 5)
    #expect(PasswordQuery.wordCount(forLength: 32) == 6)
    #expect(PasswordQuery.wordCount(forLength: PasswordQuery.lengthLimits.upperBound) == 11)
    // 128 is past what `request(from:)` will hand over, so this is the pure
    // function's own guard rather than a reachable case. Kept because the
    // upper clamp is the only thing stopping an unbounded word count if the
    // length limit is ever raised.
    #expect(PasswordQuery.wordCount(forLength: 128) == PasswordQuery.passphraseWordLimits.upperBound)
    #expect(PasswordStrength(recipe: .words(count: 5, separator: "-")).label != "Weak")
}

// MARK: - The word list

/// The list is a shipped resource, so a missing or mangled file is a real
/// failure mode — and it would surface as a silently absent passphrase row.
/// These are the properties the strength figure and the readability claim rest
/// on, checked against the file that actually ships.
@Test func wordListShipsIntactAndIsExactlyAPowerOfTwo() {
    let words = PassphraseWords.all
    #expect(words.count == PassphraseWords.expectedCount)
    #expect(words.count == 1 << PassphraseWords.bitsPerWord)
    #expect(Set(words).count == words.count, "duplicates would overstate the entropy")
    #expect(words.allSatisfy { $0.count >= 3 && $0.count <= 8 })
    #expect(words.allSatisfy { $0.allSatisfy { $0.isASCII && $0.isLowercase } })
    // BIP-39's defining property, and the reason the words are retypable: no
    // two share their first four letters.
    #expect(Set(words.map { $0.prefix(4) }).count == words.count)
}

// MARK: - Generation

@Test func generatorHonoursLengthAndPool() {
    let words = SeededWords(seed: 1)
    let password = PasswordGenerator.generate(
        .characters(length: 24, alphabet: .everything),
        randomWord: words.source
    )

    #expect(password.count == 24)
    let allowed = Set("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789")
        .union(PasswordAlphabet.symbolCharacters)
    #expect(password.allSatisfy(allowed.contains))
}

/// A password that promises symbols and contains none fails the form it was
/// generated for, so every selected class must actually appear.
@Test func generatorSeedsOneCharacterFromEveryClass() {
    for seed in UInt64(1)...50 {
        let words = SeededWords(seed: seed)
        let password = PasswordGenerator.generate(
            .characters(length: 12, alphabet: .everything),
            randomWord: words.source
        )
        #expect(password.contains { $0.isLowercase }, "seed \(seed)")
        #expect(password.contains { $0.isUppercase }, "seed \(seed)")
        #expect(password.contains { $0.isNumber }, "seed \(seed)")
        #expect(
            password.contains(where: PasswordAlphabet.symbolCharacters.contains),
            "seed \(seed)"
        )
    }
}

/// Fewer characters than classes: seeding all four would overrun the length.
@Test func generatorNeverExceedsAShortLength() {
    let words = SeededWords(seed: 7)
    let password = PasswordGenerator.generate(
        .characters(length: 2, alphabet: .everything),
        randomWord: words.source
    )
    #expect(password.count == 2)
}

@Test func passphraseJoinsRealWordsWithASeparator() {
    let words = SeededWords(seed: 13)
    let passphrase = PasswordGenerator.generate(
        .words(count: 5, separator: "-"),
        randomWord: words.source
    )

    let parts = passphrase.split(separator: "-").map(String.init)
    #expect(parts.count == 5)
    #expect(parts.allSatisfy(Set(PassphraseWords.all).contains))
    #expect(!passphrase.hasPrefix("-"))
    #expect(!passphrase.hasSuffix("-"))
}

/// Words are drawn with replacement. Rejecting a repeat would turn this into
/// selection without replacement and quietly cost the entropy that the
/// 11-bits-per-word figure on screen claims.
@Test func passphraseAllowsARepeatedWord() {
    // Every value is a multiple of the vocabulary size, so each draw lands on
    // index 0 and all six words come out identical. Waiting for a natural
    // collision instead would be a coin flip: six draws from 2048 repeat about
    // 0.7% of the time, which is a test that fails on someone else's machine.
    //
    // The values also step upward rather than staying constant. A constant
    // source can deadlock `next(upperBound:)`, which rejection-samples and
    // would reject the same too-small value forever.
    let counter = SteppingWords(step: UInt64(PassphraseWords.expectedCount))
    let passphrase = PasswordGenerator.generate(
        .words(count: 6, separator: "-"),
        randomWord: counter.source
    )

    let parts = passphrase.split(separator: "-").map(String.init)
    #expect(parts.count == 6)
    #expect(Set(parts).count == 1, "de-duplication would cost the claimed entropy")
    #expect(parts.allSatisfy { $0 == PassphraseWords.all[0] })
}

@Test func generatorIsDrivenEntirelyByItsSource() {
    for recipe: PasswordRecipe in [
        .characters(length: 20, alphabet: .everything),
        .words(count: 5, separator: "-")
    ] {
        let first = PasswordGenerator.generate(recipe, randomWord: SeededWords(seed: 42).source)
        let same = PasswordGenerator.generate(recipe, randomWord: SeededWords(seed: 42).source)
        let other = PasswordGenerator.generate(recipe, randomWord: SeededWords(seed: 43).source)
        #expect(first == same)
        #expect(first != other)
    }
}

/// The real source, exercised once: it must not return a constant, and must
/// not return the zeroed buffer its failure path exists to avoid.
@Test func secureSourceProducesDistinctPasswords() {
    let generated = Set((0..<25).map { _ in
        PasswordGenerator.generate(.characters(length: 20, alphabet: .everything))
    })
    #expect(generated.count == 25)
}

@Test func strengthReportsEntropyAndALabel() {
    // 20 characters over an 85-glyph pool: 20 × log2(85) ≈ 128.2 bits, and the
    // estimate rounds down rather than flattering itself.
    #expect(PasswordAlphabet.everything.pools.reduce(0) { $0 + $1.count } == 85)
    let strong = PasswordStrength(recipe: .characters(length: 20, alphabet: .everything))
    #expect(strong.bits == 128)
    #expect(strong.summary == "128 bits · Very strong")

    // Word recipes are exact rather than estimated: 2048 is 2^11.
    #expect(PasswordStrength(recipe: .words(count: 5, separator: "-")).bits == 55)
    #expect(PasswordStrength(recipe: .words(count: 5, separator: "-")).label == "Fair")
    #expect(PasswordStrength(recipe: .words(count: 9, separator: "-")).label == "Very strong")

    // A 6-digit PIN really is weak, and says so.
    let pin = PasswordStrength(recipe: .characters(length: 6, alphabet: .digits))
    #expect(pin.bits == 19)
    #expect(pin.label == "Weak")
}

@Test func recipesReportTheirOwnUnit() {
    #expect(PasswordRecipe.characters(length: 20, alphabet: .digits).sizeDescription
        == "20 characters")
    #expect(PasswordRecipe.words(count: 5, separator: "-").sizeDescription == "5 words")
    #expect(PasswordRecipe.words(count: 1, separator: "-").sizeDescription == "1 word")
    #expect(PasswordRecipe.characters(length: 1, alphabet: .digits).sizeDescription
        == "1 character")
}

// MARK: - Provider

@MainActor
@Test func providerOffersOneRowPerVariant() async throws {
    let provider = PasswordProvider(randomWord: SeededWords(seed: 11).source)
    let results = try await provider.results(
        for: ParsedQuery(mode: .general, term: "password"))

    #expect(results.map(\.id) == [
        "password:strong",
        "password:alphanumeric",
        "password:passphrase",
        "password:pin"
    ])
    #expect(results.map(\.badge) == ["Strong", "Letters & digits", "Passphrase", "PIN"])
    #expect(results.map(\.sortHint) == [0, 1, 2, 3])
    // Every row carries a hero, so whichever ranks first fills the card.
    #expect(results.allSatisfy { $0.hero != nil })
    #expect(results.allSatisfy { $0.providerID == .password })
}

/// The row the user asked for: readable words, not `aQ8bSmXW4td7yQ5yneJy`.
@MainActor
@Test func passphraseRowReadsAsWords() async throws {
    let provider = PasswordProvider(randomWord: SeededWords(seed: 21).source)
    let results = try await provider.results(
        for: ParsedQuery(mode: .general, term: "password"))
    let row = try #require(results.first { $0.id == "password:passphrase" })

    #expect(row.title.split(separator: "-").count == 5)
    #expect(row.subtitle == "5 words · 55 bits · Fair")
    #expect(row.hero?.left == "5 words")
    #expect(row.hero?.leftBadge == "from 2048 words")
}

/// The id is written to disk by `UsageStore` on every ⏎. A generated secret
/// has no business in a frecency file, and neither has one anywhere else that
/// outlives the palette.
@Test func providerKeepsTheSecretOutOfEveryPersistedField() async throws {
    let provider = PasswordProvider(randomWord: SeededWords(seed: 5).source)
    let results = try await provider.results(
        for: ParsedQuery(mode: .general, term: "password"))

    for row in results {
        let password = row.title
        #expect(!password.isEmpty)
        #expect(!row.id.contains(password))
        #expect(row.subtitle?.contains(password) != true)
        #expect(!row.keywords.contains { $0.contains(password) })
        #expect(row.action == .copySecret(password))
        #expect(row.hero?.right == password)
    }
}

@Test func providerMarksItsCopiesSecret() async throws {
    let provider = PasswordProvider(randomWord: SeededWords(seed: 9).source)
    let results = try await provider.results(
        for: ParsedQuery(mode: .general, term: "pw"))

    // Never a plain `.copyText`: that write reaches the pasteboard unmarked
    // and Bopop's own watcher would record it half a second later.
    for row in results {
        guard case .copySecret = row.action else {
            Issue.record("expected copySecret, got \(row.action)")
            continue
        }
        #expect(row.action.role == .copy)
    }
}

@MainActor
@Test func providerFollowsAnExplicitLength() async throws {
    let provider = PasswordProvider(randomWord: SeededWords(seed: 2).source)
    let results = try await provider.results(
        for: ParsedQuery(mode: .general, term: "password 32"))

    #expect(results.prefix(2).allSatisfy { $0.title.count == 32 })
    // Six words is "enough to fill 32 characters", not 32 words.
    #expect(try #require(results.first { $0.id == "password:passphrase" })
        .title.split(separator: "-").count == 6)
    // A 32-digit PIN is not a PIN.
    #expect(results.last?.title.count == PasswordQuery.pinLengthLimit)
}

@MainActor
@Test func providerIsQuietOutsideGeneralMode() async throws {
    let provider = PasswordProvider(randomWord: SeededWords(seed: 1).source)
    #expect(try await provider.results(
        for: ParsedQuery(mode: .clipboard, term: "password")).isEmpty)
    #expect(try await provider.results(
        for: ParsedQuery(mode: .general, term: "passport")).isEmpty)
}

// MARK: - Ranking

private func rankedIDs(_ results: [SearchResult], query: String) -> [String] {
    Ranker.rank(
        results,
        query: query,
        frecencyFor: { _ in 0 },
        providerWeights: Ranker.defaultWeights
    ).map(\.id)
}

private let passwordsApp = SearchResult(
    id: "app:passwords",
    providerID: .apps,
    title: "Passwords",
    action: .openApp("/System/Applications/Passwords.app"),
    sortHint: 0
)

/// `password 32` matches none of the trigger vocabulary, so without the term
/// in `keywords` Ranker would drop every row and the length would silently do
/// nothing.
@MainActor
@Test func explicitLengthRowsSurviveRanking() async throws {
    let provider = PasswordProvider(randomWord: SeededWords(seed: 4).source)
    let results = try await provider.results(
        for: ParsedQuery(mode: .general, term: "password 32"))
    #expect(rankedIDs(results, query: "password 32").count == results.count)
}

/// The generator sits below the user's own Passwords app on the words that
/// name the app, and above it only on the words that name the generator.
@MainActor
@Test func generatorAndPasswordsAppTakeTurnsAtTheTop() async throws {
    let provider = PasswordProvider(randomWord: SeededWords(seed: 6).source)

    // `keepsApp` is false only for "passphrase", which does not match the word
    // "Passwords" at any tier — Ranker drops it, and that is correct. Asserting
    // otherwise would be asserting a bug.
    for (term, expectedTop, keepsApp) in [
        ("pass", "app:passwords", true),
        ("passwords", "app:passwords", true),
        ("password", "password:strong", true),
        ("pw", "password:strong", true),
        ("passphrase", "password:strong", false)
    ] {
        let results = try await provider.results(
            for: ParsedQuery(mode: .general, term: term))
        let ranked = rankedIDs(results + [passwordsApp], query: term)
        #expect(ranked.first == expectedTop, "\(term) ranked \(ranked)")
        // Losing the top spot must not mean falling out of the list.
        #expect(ranked.contains("app:passwords") == keepsApp, "\(term) ranked \(ranked)")
        #expect(ranked.contains("password:strong"), "\(term) ranked \(ranked)")
    }
}

// MARK: - Large Type

@Test func largeTypeBlowsUpAGeneratedPassword() {
    let result = SearchResult(
        id: "password:strong",
        providerID: .password,
        title: "aB3!xQ",
        action: .copySecret("aB3!xQ"),
        sortHint: 0
    )
    #expect(LargeType.text(for: result) == "aB3!xQ")
}

// MARK: - Focus

/// Four rows carry near-identical payloads, so which one ⏎ copies is not
/// guessable from the screen. The card has to own ⏎ on first paint, and the
/// password it shows has to be the one that gets copied.
@MainActor
@Test func heroOwnsReturnOnFirstPaintOfAPasswordQuery() async throws {
    let state = PaletteState(configuration: PaletteStateConfiguration(
        orderedModes: Mode.restingModes, gridColumns: 8))
    let typed = state.setQueryText("password")
    let produced = try await PasswordProvider(randomWord: SeededWords(seed: 31).source)
        .results(for: typed.query)
    let ranked = Ranker.rank(
        produced,
        query: typed.query.term,
        frecencyFor: { _ in 0 },
        providerWeights: Ranker.defaultWeights
    )

    let plan = state.apply(QueryEngine.Update(
        query: typed.query, results: ranked, generation: 1, isFinal: true))

    #expect(plan.focus == .hero)
    #expect(plan.hero?.id == "password:strong")
    #expect(plan.focusedResult?.id == "password:strong")
    #expect(plan.focusedResult?.action == plan.hero?.action)
    // One ↓ moves to the first row under the card, which is where both
    // screenshots of this feature were taken.
    #expect(state.moveSelection(.down).focusedResult?.id == "password:alphanumeric")
}
