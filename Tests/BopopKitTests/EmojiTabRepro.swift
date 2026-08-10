import Foundation
import Testing
@testable import BopopKit

private nonisolated final class ModeProvider: ResultProvider {
    let id: ProviderID
    private let make: @Sendable (ParsedQuery) -> [SearchResult]
    init(id: ProviderID, make: @escaping @Sendable (ParsedQuery) -> [SearchResult]) {
        self.id = id
        self.make = make
    }
    func results(for query: ParsedQuery) async throws -> [SearchResult] { make(query) }
}

/// Leaving the emoji tab must search the mode you land on. Drives a real
/// QueryEngine so the whole loop — plan, effect, engine, update, plan — is
/// exercised rather than the state machine alone.
@MainActor
@Test
func emojiTabThenAnotherTabStillReturnsResults() async {
    let apps = ModeProvider(id: .apps) { q in
        ["Safari", "Mail"].filter { q.term.isEmpty || $0.lowercased().contains(q.term.lowercased()) }
            .map { SearchResult(id: "app:\($0)", providerID: .apps, title: $0, action: .copyText($0), sortHint: 0) }
    }
    let emoji = ModeProvider(id: .emoji) { _ in
        (0..<5).map { SearchResult(id: "emoji:\($0)", providerID: .emoji, title: "e\($0)", action: .copyText("e"), sortHint: $0) }
    }
    let engine = QueryEngine(
        providers: [.general: [apps], .apps: [apps], .emoji: [emoji]],
        debounce: [:],
        settle: .zero
    )
    let palette = PaletteState(
        configuration: PaletteStateConfiguration(
            orderedModes: [.general, .apps, .fileSearch, .clipboard, .emoji, .translation],
            gridColumns: 10
        )
    )
    var last: PaletteRenderPlan?
    engine.onUpdate = { last = palette.apply($0) }

    /// Runs the plan's effects and waits for the engine to answer that exact
    /// query. Polling rather than sleeping: a fixed delay is a latency
    /// assertion this test does not mean to make, and it flakes under the
    /// suite's parallel load.
    func run(_ plan: PaletteRenderPlan) async {
        var pending: ParsedQuery?
        for effect in plan.effects {
            if case let .runQuery(q) = effect {
                pending = q
                engine.update(query: q)
            }
        }
        guard let pending else { return }
        let clock = ContinuousClock()
        let deadline = clock.now + .seconds(10)
        while clock.now < deadline, last?.query != pending {
            try? await Task.sleep(for: .milliseconds(1))
        }
    }

    await run(palette.enterMode(.emoji))
    #expect(last?.rows.count == 5)

    await run(palette.enterMode(.apps))
    #expect(last?.query.mode == .apps)

    await run(palette.setQueryText("saf"))

    #expect(last?.rows.map(\.id) == ["app:Safari"])
}
