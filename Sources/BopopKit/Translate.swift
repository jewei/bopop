import Foundation

public nonisolated enum TranslationTarget: String, Sendable, Equatable {
    case english = "en"
    case chineseSimplified = "zh-Hans"
    case chineseTraditional = "zh-Hant"
}

public nonisolated enum TranslationDirection {
    private static let hanRanges: [ClosedRange<UInt32>] = [
        0x4E00...0x9FFF,
        0x3400...0x4DBF,
        0xF900...0xFAFF
    ]

    /// Han chars present → .english, else → chineseVariant
    public static func target(
        for text: String,
        chineseVariant: TranslationTarget
    ) -> TranslationTarget {
        let containsHan = text.unicodeScalars.contains { scalar in
            hanRanges.contains { $0.contains(scalar.value) }
        }
        return containsHan ? .english : chineseVariant
    }
}

public nonisolated enum TranslatorAvailability: Sendable, Equatable {
    case ready
    case needsDownload
    case unsupported
}

public protocol Translator: Sendable {
    func availability(target: TranslationTarget) async -> TranslatorAvailability
    func translate(_ text: String, to target: TranslationTarget) async throws -> String
    func requestDownload(target: TranslationTarget) async
}

public final class TranslationProvider: ResultProvider {
    public let id: ProviderID = .translation

    private let translator: Translator
    private let chineseVariant: @Sendable () async -> TranslationTarget
    private let debounceNanoseconds: UInt64

    public init(
        translator: Translator,
        chineseVariant: @escaping @Sendable () async -> TranslationTarget,
        debounceNanoseconds: UInt64 = 300_000_000
    ) {
        self.translator = translator
        self.chineseVariant = chineseVariant
        self.debounceNanoseconds = debounceNanoseconds
    }

    public nonisolated func results(for query: ParsedQuery) async throws -> [SearchResult] {
        guard query.mode == .translation else {
            return []
        }
        let term = query.term.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty else {
            return []
        }

        let target = TranslationDirection.target(for: term, chineseVariant: await chineseVariant())

        switch await translator.availability(target: target) {
        case .unsupported:
            return [
                SearchResult(
                    id: "translate:unsupported",
                    providerID: .translation,
                    title: "Translation not available on this Mac",
                    icon: .symbol("exclamationmark.triangle"),
                    keywords: [query.term],
                    action: .enterMode(.translation),
                    sortHint: 0
                )
            ]
        case .needsDownload:
            return [
                SearchResult(
                    id: "translate:download",
                    providerID: .translation,
                    title: "Download Chinese ⇄ English translation…",
                    icon: .symbol("arrow.down.circle"),
                    keywords: [query.term],
                    action: .downloadTranslation,
                    sortHint: 0
                )
            ]
        case .ready:
            break
        }

        try? await Task.sleep(nanoseconds: debounceNanoseconds)
        guard !Task.isCancelled else {
            return []
        }

        guard let translated = try? await translator.translate(term, to: target) else {
            return []
        }

        let sourceIsChinese = target == .english
        let hero = HeroContent(
            left: term,
            leftBadge: sourceIsChinese ? "Chinese" : "English",
            right: translated,
            rightBadge: Self.displayName(for: target)
        )
        return [
            SearchResult(
                id: "translate",
                providerID: .translation,
                title: translated,
                icon: .symbol("character.bubble"),
                keywords: [query.term],
                action: .copyText(translated),
                hero: hero,
                sortHint: 0
            )
        ]
    }

    private nonisolated static func displayName(for target: TranslationTarget) -> String {
        switch target {
        case .english: return "English"
        case .chineseSimplified: return "Simplified Chinese"
        case .chineseTraditional: return "Traditional Chinese"
        }
    }
}
