import Foundation

public nonisolated enum DictionaryQuery {
    public static func word(from term: String) -> String? {
        let trimmed = term.trimmingCharacters(in: .whitespacesAndNewlines)
        for prefix in ["define ", "def "] {
            guard trimmed.lowercased().hasPrefix(prefix) else { continue }
            let word = String(trimmed.dropFirst(prefix.count))
                .trimmingCharacters(in: .whitespaces)
            return word.isEmpty ? nil : word
        }
        return nil
    }
}

public final class DictionaryProvider: ResultProvider {
    public let id: ProviderID = .dictionary

    private let lookup: @Sendable (String) -> String?

    public init(lookup: @escaping @Sendable (String) -> String?) {
        self.lookup = lookup
    }

    public nonisolated func results(for query: ParsedQuery) async throws -> [SearchResult] {
        guard query.mode == .general,
              let word = DictionaryQuery.word(from: query.term),
              // lookup wraps DCSCopyTextDefinition, a thread-safe C API — safe to
              // call synchronously from this now off-main-actor provider body.
              let definition = lookup(word) else {
            return []
        }

        guard let encodedWord = word.addingPercentEncoding(
            withAllowedCharacters: .urlPathAllowed) else {
            return []
        }
        let hero = HeroContent(
            left: word,
            leftBadge: "Define",
            right: Self.excerpt(definition, droppingLeading: word, limit: 120),
            note: "Return opens Dictionary"
        )
        return [
            SearchResult(
                id: "dict:\(word)",
                providerID: .dictionary,
                title: "Define \"\(word)\"",
                subtitle: Self.excerpt(definition, droppingLeading: word, limit: 80),
                icon: .symbol("character.book.closed"),
                keywords: [query.term],
                action: .openURL("dict://\(encodedWord)"),
                secondaryActions: [.copyText(definition)],
                hero: hero,
                sortHint: 0
            )
        ]
    }

    /// The system definition begins by repeating the headword; drop it so the
    /// hero pane leads with the sense text.
    private nonisolated static func excerpt(
        _ definition: String,
        droppingLeading word: String,
        limit: Int
    ) -> String {
        var text = definition
        if text.lowercased().hasPrefix(word.lowercased()) {
            text = String(text.dropFirst(word.count))
            text = text.trimmingCharacters(
                in: CharacterSet(charactersIn: " |").union(.whitespaces))
        }
        guard text.count > limit else { return text }
        return String(text.prefix(limit)) + "…"
    }
}
