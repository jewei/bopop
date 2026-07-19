import Foundation
import Testing
@testable import BopopKit

// Diagnostic for the "empty palette on show" regression: replicates
// AppDelegate's general-mode wiring and asserts the empty query yields
// the two mode commands at minimum.
@MainActor
@Test
func emptyQueryProducesCommandRows() async throws {
    let engine = QueryEngine(
        providers: [
            .general: [CommandsProvider()],
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
    #expect(final.results.count >= 4)
    #expect(final.results.contains { $0.id == "cmd:file-search" })
    #expect(final.results.contains { $0.id == "cmd:emoji" })
    #expect(final.results.contains { $0.id == "cmd:translate" })
}
