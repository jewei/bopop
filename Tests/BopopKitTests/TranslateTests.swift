import Foundation
import Testing
@testable import BopopKit

@Test(arguments: [
    ("hello", TranslationTarget.chineseTraditional, TranslationTarget.chineseTraditional),
    ("你好", .chineseSimplified, .english),
    ("hello 你好", .chineseTraditional, .english),
    ("123 456", .chineseSimplified, .chineseSimplified)
])
func translationDirectionDetectsSource(
    text: String,
    variant: TranslationTarget,
    expected: TranslationTarget
) {
    #expect(TranslationDirection.target(for: text, chineseVariant: variant) == expected)
}

@MainActor
@Test
func emptyTermReturnsNoResults() async throws {
    let translator = MockTranslator()
    let provider = TranslationProvider(
        translator: translator,
        chineseVariant: { .chineseSimplified },
        debounceNanoseconds: 0
    )
    let results = try await provider.results(for: ParsedQuery(mode: .translation, term: ""))
    #expect(results.isEmpty)
    #expect(await translator.availabilityCallCount == 0)
}

@MainActor
@Test
func wrongModeReturnsNoResults() async throws {
    let translator = MockTranslator()
    let provider = TranslationProvider(
        translator: translator,
        chineseVariant: { .chineseSimplified },
        debounceNanoseconds: 0
    )
    let results = try await provider.results(for: ParsedQuery(mode: .general, term: "hello"))
    #expect(results.isEmpty)
    #expect(await translator.availabilityCallCount == 0)
}

@MainActor
@Test
func readyFlowProducesHeroAndCopyAction() async throws {
    let translator = MockTranslator(availability: .ready, translationResult: .success("你好"))
    let provider = TranslationProvider(
        translator: translator,
        chineseVariant: { .chineseSimplified },
        debounceNanoseconds: 0
    )
    let results = try await provider.results(for: ParsedQuery(mode: .translation, term: "hello"))
    let result = try #require(results.first)
    #expect(result.action == .copyText("你好"))
    let hero = try #require(result.hero)
    #expect(hero.left == "hello")
    #expect(hero.leftBadge == "English")
    #expect(hero.right == "你好")
    #expect(hero.rightBadge == "Simplified Chinese")
    #expect(await translator.lastTranslateTarget == .chineseSimplified)
}

@MainActor
@Test
func readyFlowDetectsChineseSourceForEnglishTarget() async throws {
    let translator = MockTranslator(availability: .ready, translationResult: .success("hello"))
    let provider = TranslationProvider(
        translator: translator,
        chineseVariant: { .chineseTraditional },
        debounceNanoseconds: 0
    )
    let results = try await provider.results(for: ParsedQuery(mode: .translation, term: "你好"))
    let hero = try #require(results.first?.hero)
    #expect(hero.leftBadge == "Chinese")
    #expect(hero.rightBadge == "English")
}

@MainActor
@Test
func needsDownloadRow() async throws {
    let translator = MockTranslator(availability: .needsDownload)
    let provider = TranslationProvider(
        translator: translator,
        chineseVariant: { .chineseSimplified },
        debounceNanoseconds: 0
    )
    let results = try await provider.results(for: ParsedQuery(mode: .translation, term: "hello"))
    #expect(results.first?.title == "Download Chinese ⇄ English translation…")
    #expect(results.first?.action == .downloadTranslation)
    #expect(await translator.translateCallCount == 0)
}

@MainActor
@Test
func unsupportedRow() async throws {
    let translator = MockTranslator(availability: .unsupported)
    let provider = TranslationProvider(
        translator: translator,
        chineseVariant: { .chineseSimplified },
        debounceNanoseconds: 0
    )
    let results = try await provider.results(for: ParsedQuery(mode: .translation, term: "hello"))
    #expect(results.first?.title == "Translation not available on this Mac")
    #expect(await translator.translateCallCount == 0)
}

@MainActor
@Test
func translateFailureReturnsNoResults() async throws {
    let translator = MockTranslator(availability: .ready, translationResult: .failure(MockTranslatorError.boom))
    let provider = TranslationProvider(
        translator: translator,
        chineseVariant: { .chineseSimplified },
        debounceNanoseconds: 0
    )
    let results = try await provider.results(for: ParsedQuery(mode: .translation, term: "hello"))
    #expect(results.isEmpty)
}

@MainActor
@Test
func debounceCancellationStopsTranslate() async {
    let translator = MockTranslator(availability: .ready, translationResult: .success("你好"))
    let provider = TranslationProvider(
        translator: translator,
        chineseVariant: { .chineseSimplified },
        debounceNanoseconds: 200_000_000
    )

    let task = Task {
        try await provider.results(for: ParsedQuery(mode: .translation, term: "hello"))
    }

    await translator.waitUntilAvailabilityChecked()
    task.cancel()
    let results = try? await task.value

    #expect(results == [])
    #expect(await translator.translateCallCount == 0)
}

private enum MockTranslatorError: Error {
    case boom
}

private actor MockTranslator: Translator {
    private let scriptedAvailability: TranslatorAvailability
    private let scriptedTranslation: Result<String, Error>
    private(set) var availabilityCallCount = 0
    private(set) var translateCallCount = 0
    private(set) var requestDownloadCallCount = 0
    private(set) var lastTranslateTarget: TranslationTarget?
    private var availabilityChecked = false
    private var availabilityCheckedContinuations: [CheckedContinuation<Void, Never>] = []

    init(
        availability: TranslatorAvailability = .ready,
        translationResult: Result<String, Error> = .success("")
    ) {
        scriptedAvailability = availability
        scriptedTranslation = translationResult
    }

    func availability(target: TranslationTarget) async -> TranslatorAvailability {
        availabilityCallCount += 1
        availabilityChecked = true
        availabilityCheckedContinuations.forEach { $0.resume() }
        availabilityCheckedContinuations.removeAll()
        return scriptedAvailability
    }

    func translate(_ text: String, to target: TranslationTarget) async throws -> String {
        translateCallCount += 1
        lastTranslateTarget = target
        return try scriptedTranslation.get()
    }

    func requestDownload(target: TranslationTarget) async {
        requestDownloadCallCount += 1
    }

    func waitUntilAvailabilityChecked() async {
        if availabilityChecked {
            return
        }
        await withCheckedContinuation { continuation in
            availabilityCheckedContinuations.append(continuation)
        }
    }
}
