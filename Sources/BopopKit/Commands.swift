import Foundation

/// Mode-entry command rows for All mode ("Snippets…"). Mirrors the
/// translation command row (Translate.swift) but for modes without a
/// resting tab pill.
public final class CommandsProvider: ResultProvider {
    public let id: ProviderID = .commands

    public init() {}

    public func results(for query: ParsedQuery) async throws -> [SearchResult] {
        guard query.mode == .general,
              !query.term.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return []
        }
        return [
            SearchResult(
                id: "command:snippets",
                providerID: .commands,
                title: "Snippets…",
                icon: .symbol("text.quote"),
                keywords: ["snippets", "snippet"],
                action: .enterMode(.snippets),
                sortHint: 0
            )
        ]
    }
}
