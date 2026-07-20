import Foundation
import Testing
@testable import BopopKit

// Diagnostic for the "empty palette on show" regression: an empty query
// must still publish a final update containing whatever the general-mode
// providers yield for an empty term. (The mode command rows this test
// originally asserted were removed when the tab row replaced them.)
@MainActor
@Test
func emptyQueryPublishesProviderResults() async throws {
    struct StubProvider: ResultProvider {
        let id: ProviderID = .apps

        func results(for query: ParsedQuery) async throws -> [SearchResult] {
            [
                SearchResult(
                    id: "stub:frecent-app",
                    providerID: .apps,
                    title: "Stub App",
                    action: .openApp("stub"),
                    sortHint: 0
                )
            ]
        }
    }

    let engine = QueryEngine(
        providers: [
            .general: [StubProvider()],
            .fileSearch: [],
            .clipboard: []
        ],
        debounce: [:]
    )

    var received: [QueryEngine.Update] = []
    engine.onUpdate = { received.append($0) }
    engine.update(raw: "", stickyMode: .general)

    for _ in 0..<200 where !(received.last?.isFinal ?? false) {
        try await Task.sleep(for: .milliseconds(5))
    }

    let final = try #require(received.last)
    #expect(final.isFinal)
    #expect(final.results.contains { $0.id == "stub:frecent-app" })
}
