import BopopKit
import Foundation

// TODO(step 4): delete DemoProvider
final class DemoProvider: ResultProvider {
    let id: ProviderID = .apps

    func results(for query: ParsedQuery) async throws -> [SearchResult] {
        guard query.mode == .general else {
            return []
        }

        return Self.items.enumerated().map { index, item in
            SearchResult(
                id: "demo:\(item.name.lowercased().replacingOccurrences(of: " ", with: "-"))",
                providerID: .apps,
                title: item.name,
                subtitle: item.subtitle,
                icon: .symbol(item.symbol),
                keywords: item.keywords,
                action: .copyText(item.name),
                sortHint: index
            )
        }
    }

    private static let items = [
        Item(name: "Safari", subtitle: "Demo application", symbol: "safari", keywords: ["browser", "web"]),
        Item(name: "Google Chrome", subtitle: "Demo application", symbol: "globe", keywords: ["browser", "web"]),
        Item(name: "Visual Studio Code", subtitle: "Demo application", symbol: "chevron.left.forwardslash.chevron.right", keywords: ["code", "editor"]),
        Item(name: "Notes", subtitle: "Demo application", symbol: "note.text", keywords: ["write", "memo"]),
        Item(name: "Calendar", subtitle: "Demo application", symbol: "calendar", keywords: ["events", "schedule"]),
        Item(name: "Terminal", subtitle: "Demo application", symbol: "terminal", keywords: ["shell", "command"])
    ]

    private struct Item: Sendable {
        let name: String
        let subtitle: String
        let symbol: String
        let keywords: [String]
    }
}
