import Foundation

public final class CommandsProvider: ResultProvider {
    public let id: ProviderID = .commands

    public init() {}

    public func results(for query: ParsedQuery) async throws -> [SearchResult] {
        guard query.mode == .general else {
            return []
        }

        return [
            SearchResult(
                id: "cmd:file-search",
                providerID: .commands,
                title: "Search Files…",
                icon: .symbol("magnifyingglass"),
                keywords: ["files", "find"],
                action: .enterMode(.fileSearch),
                sortHint: 0
            ),
            SearchResult(
                id: "cmd:clipboard",
                providerID: .commands,
                title: "Clipboard History…",
                icon: .symbol("doc.on.clipboard"),
                keywords: ["clipboard", "paste", "history"],
                action: .enterMode(.clipboard),
                sortHint: 1
            )
        ]
    }
}
