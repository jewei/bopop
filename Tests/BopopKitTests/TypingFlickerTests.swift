import Foundation
import Testing
@testable import BopopKit

// Regression suite for "results flicker while typing".
//
// The palette re-renders once per `QueryEngine.Update`, so a frame here is one
// thing the user's eye actually sees. These tests drive the real general-mode
// provider set through the real engine and into a real `PaletteState`, and
// assert on the plans it returns.
//
// This file used to reconstruct each frame by hand — its own header said it
// "reconstruct[s] each frame exactly the way `PaletteController.applyMeasured`
// does" — which meant the composition under test had a second copy kept in
// sync by hand, and the copy silently omitted selection restoration, the
// render-skip and grid mode. It drives the module now.
//
// Typing "safari" used to produce 54 renders across 6 keystrokes: 25 of them
// painted a genuinely empty list (every provider that matched nothing still
// emitted, and the accumulated list starts empty), and 6 of them shoved an
// already-visible row down the list when a slower, higher-ranking provider
// landed.

/// One rendered palette state, taken straight off the plan the module returns.
private struct Frame: Equatable {
    let query: ParsedQuery
    let isFinal: Bool
    let heroID: String?
    let rowIDs: [String]
    let focus: PaletteFocus
    let contentChanged: Bool

    var visual: String {
        "hero=\(heroID ?? "-") focus=\(focus) rows=\(rowIDs.count) \(rowIDs.prefix(5).joined(separator: ","))"
    }
}

/// A transition the user perceives as a jump rather than a smooth fill.
/// Appending below the fold is smooth; moving or removing a row that is already
/// on screen — or swapping the hero card, which resizes the panel too — is not.
private struct Disruption {
    let reason: String
}

/// Pairs each plan with the update that produced it — `isFinal` is a fact
/// about the publication, not about what gets drawn.
@MainActor
private func frames(
    _ plans: [PaletteRenderPlan],
    _ updates: [QueryEngine.Update]
) -> [Frame] {
    zip(plans, updates).map { plan, update in
        Frame(
            query: plan.query,
            isFinal: update.isFinal,
            heroID: plan.hero?.id,
            rowIDs: plan.rows.map(\.id),
            focus: plan.focus,
            contentChanged: plan.contentChanged
        )
    }
}

private func disruptions(in frames: [Frame]) -> [Disruption] {
    var found: [Disruption] = []
    // Only within one keystroke: across keystrokes the rows are supposed to
    // change, that is the filtering working.
    for (previous, next) in zip(frames, frames.dropFirst())
    where previous.query == next.query {
        if previous.heroID != next.heroID {
            found.append(
                Disruption(
                    reason: "hero changed \(previous.heroID ?? "-") -> \(next.heroID ?? "-")"
                )
            )
        } else if !next.rowIDs.starts(with: previous.rowIDs) {
            found.append(Disruption(reason: "visible rows reordered/removed"))
        }
    }
    return found
}

/// The frame-by-frame timeline, attached to the expectations as a comment so it
/// shows up when one fails and stays out of the way when they pass.
@MainActor
private func timeline(_ frames: [Frame]) -> Comment {
    var lines = ["\(frames.count) frame(s):"]
    for (index, frame) in frames.enumerated() {
        lines.append(
            "  [\(index)] term='\(frame.query.term)' final=\(frame.isFinal) \(frame.visual)"
        )
    }
    for disruption in disruptions(in: frames) {
        lines.append("  !! \(disruption.reason)")
    }
    return Comment(rawValue: lines.joined(separator: "\n"))
}

// MARK: - Regressions

/// One keystroke, one render: when every provider finishes inside the settle
/// window the palette paints once with the settled list, rather than nine times
/// as each provider trickles in.
///
/// The window here is far longer than the harness's slowest provider (12ms) on
/// purpose, and costs the test nothing — a window only ever fires when
/// providers are still outstanding, so this returns as soon as the last one
/// lands. A window near the production 50ms would instead make this test
/// assert how fast the machine is: under the full suite's parallel load the
/// providers routinely run past 50ms, the engine publishes early exactly as
/// designed, and the frame count changes for reasons that have nothing to do
/// with this bug.
@MainActor
@Test
func keystrokeRendersASingleFrame() async {
    let engine = await makeGeneralEngine(settle: .milliseconds(750))
    let recorder = FrameRecorder()
    engine.onUpdate = recorder.record

    recorder.type("safari", into: engine)
    await recorder.waitForFinal()

    let captured = frames(recorder.plans, recorder.updates)
    let trace = timeline(captured)

    #expect(disruptions(in: captured).isEmpty, trace)
    #expect(captured.count == 1, trace)
}

/// The user's actual scenario. Six keystrokes must cost six renders, with no
/// blank frame and no visible row shoved out from under the pointer.
@MainActor
@Test
func typingAWordRendersOneFramePerKeystroke() async {
    let engine = await makeGeneralEngine()
    let recorder = FrameRecorder()
    engine.onUpdate = recorder.record

    var typed = ""
    for character in "safari" {
        typed.append(character)
        recorder.type(typed, into: engine)
        try? await Task.sleep(for: .milliseconds(60))
    }
    await recorder.waitForFinal()

    let captured = frames(recorder.plans, recorder.updates)
    let trace = timeline(captured)

    let blanks = captured.filter { $0.rowIDs.isEmpty && !$0.isFinal }
    #expect(blanks.isEmpty, trace)
    #expect(disruptions(in: captured).isEmpty, trace)
    // Was 54. At most one render per keystroke — fewer is fine and happens
    // when a generation is superseded before it publishes at all.
    #expect(captured.count <= 6, trace)
}

/// A provider that matches nothing must not blank the list on its way past.
/// This is what produced the blink: `accumulated` starts empty each generation,
/// and the six providers that matched nothing each emitted that empty list.
@MainActor
@Test
func interimRendersAreNeverBlank() async {
    let engine = await makeGeneralEngine()
    let recorder = FrameRecorder()
    engine.onUpdate = recorder.record

    recorder.type("safari", into: engine)
    await recorder.waitForFinal()

    let blankInterim = recorder.updates.filter { !$0.isFinal && $0.results.isEmpty }
    #expect(blankInterim.isEmpty, "\(blankInterim.count) blank interim update(s)")
}

/// The settle window must not become a stall. A provider that takes far longer
/// than the window cannot hold back what has already landed — otherwise
/// enabling Currency and losing the network would leave the palette empty.
@MainActor
@Test
func slowProviderDoesNotStallTheFirstPaint() async {
    let gate = Gate()
    let fast = FakeProvider(id: .commands) { _ in
        [flickerResult(id: "cmd:fast", providerID: .commands, title: "Fast")]
    }
    let slow = FakeProvider(id: .apps) { _ in
        await gate.wait()
        return [flickerResult(id: "app:slow", title: "Slow")]
    }
    let engine = QueryEngine(
        providers: [.general: [fast, slow]],
        debounce: [:],
        settle: .milliseconds(20)
    )
    let recorder = FrameRecorder()
    engine.onUpdate = recorder.record

    // Empty query: the ranker keeps every candidate, so the assertions below
    // are about publish timing rather than about what matches "fast".
    recorder.type("", into: engine)
    await gate.waitUntilStarted()

    // Paints the fast provider's rows on the settle boundary, while the slow
    // one is still outstanding.
    let interim = await recorder.waitForUpdate { !$0.isFinal }
    #expect(interim?.results.map(\.id) == ["cmd:fast"])

    await gate.release()
    let final = await recorder.waitForUpdate(matching: \.isFinal)
    #expect(Set(final?.results.map(\.id) ?? []) == ["cmd:fast", "app:slow"])
}

// MARK: - Harness

/// The real general-mode providers, minus the two that need AppKit or the
/// network. Each is wrapped in a deterministic delay so completion order — and
/// therefore the emit sequence — is stable run to run. The delays are not
/// load-bearing: the churn reproduces with every delay set to zero.
@MainActor
private func makeGeneralEngine(settle: Duration? = nil) async -> QueryEngine {
    let catalog = AppCatalog(
        directories: [],
        extraApplicationPaths: [],
        scanner: { _, _, cache in (fixtureApps, cache) }
    )
    _ = await catalog.refreshNow()

    let providers: [(any ResultProvider, Duration)] = [
        (CalculatorProvider(), .zero),
        (CommandsProvider(), .milliseconds(1)),
        (SystemCommandsProvider(), .milliseconds(2)),
        (URLCleanProvider(), .milliseconds(3)),
        (TimeProvider(), .milliseconds(4)),
        (WebSearchProvider(engine: { .google }), .milliseconds(5)),
        (CustomSearchProvider(searches: { [] }), .milliseconds(6)),
        (DictionaryProvider(lookup: { _ in nil }), .milliseconds(8)),
        (
            AppsProvider(catalog: catalog, frecencyFor: { _ in [:] }),
            .milliseconds(12)
        )
    ]

    let wrapped = providers.map {
        LatencyProvider(wrapping: $0.0, id: $0.0.id, delay: $0.1)
    }
    guard let settle else {
        // Production default, so the typing test measures what ships.
        return QueryEngine(providers: [.general: wrapped], debounce: [:])
    }
    return QueryEngine(
        providers: [.general: wrapped],
        debounce: [:],
        settle: settle
    )
}

private let fixtureApps: [AppInfo] = [
    AppInfo(bundleID: "com.apple.Safari", name: "Safari", path: "/Applications/Safari.app", keywords: []),
    AppInfo(bundleID: "com.apple.mail", name: "Mail", path: "/Applications/Mail.app", keywords: []),
    AppInfo(bundleID: "com.apple.Terminal", name: "Terminal", path: "/Applications/Terminal.app", keywords: []),
    AppInfo(bundleID: "com.apple.Notes", name: "Notes", path: "/Applications/Notes.app", keywords: []),
    AppInfo(bundleID: "com.apple.Photos", name: "Photos", path: "/Applications/Photos.app", keywords: [])
]

/// Delays a real provider by a fixed amount without otherwise changing it.
private nonisolated final class LatencyProvider: ResultProvider {
    let id: ProviderID
    private let wrapped: any ResultProvider
    private let delay: Duration

    init(wrapping wrapped: any ResultProvider, id: ProviderID, delay: Duration) {
        self.wrapped = wrapped
        self.delay = delay
        self.id = id
    }

    func results(for query: ParsedQuery) async throws -> [SearchResult] {
        if delay > .zero {
            try await Task.sleep(for: delay)
        }
        return try await wrapped.results(for: query)
    }
}

@MainActor
private final class FakeProvider: ResultProvider {
    let id: ProviderID
    private let operation: @MainActor @Sendable (ParsedQuery) async throws -> [SearchResult]

    init(
        id: ProviderID,
        operation: @escaping @MainActor @Sendable (ParsedQuery) async throws -> [SearchResult]
    ) {
        self.id = id
        self.operation = operation
    }

    func results(for query: ParsedQuery) async throws -> [SearchResult] {
        try await operation(query)
    }
}

/// Feeds every engine update through a real `PaletteState` and keeps the plans
/// it returns. The plans are what the adapter would draw, so a frame here is a
/// frame the user would have seen — no reconstruction.
@MainActor
private final class FrameRecorder {
    let palette = PaletteState(
        configuration: PaletteStateConfiguration(
            orderedModes: [.general, .apps, .fileSearch, .clipboard, .emoji, .translation],
            gridColumns: 10
        )
    )
    private(set) var updates: [QueryEngine.Update] = []
    private(set) var plans: [PaletteRenderPlan] = []

    func record(_ update: QueryEngine.Update) {
        updates.append(update)
        plans.append(palette.apply(update))
    }

    /// Types into the module and hands whatever query it asks for to the
    /// engine — the same loop the adapter runs.
    func type(_ text: String, into engine: QueryEngine) {
        for effect in palette.setQueryText(text).effects {
            if case let .runQuery(query) = effect {
                engine.update(query: query)
            }
        }
    }

    /// Waits for the final update, then a beat longer so any trailing emit is
    /// captured too — a fix that merely defers the extra renders rather than
    /// removing them must still fail these tests.
    func waitForFinal(timeout: Duration = .seconds(10)) async {
        let clock = ContinuousClock()
        let deadline = clock.now + timeout
        while clock.now < deadline {
            if updates.contains(where: \.isFinal) {
                try? await Task.sleep(for: .milliseconds(100))
                return
            }
            try? await Task.sleep(for: .milliseconds(1))
        }
    }

    func waitForUpdate(
        timeout: Duration = .seconds(20),
        matching predicate: (QueryEngine.Update) -> Bool
    ) async -> QueryEngine.Update? {
        let clock = ContinuousClock()
        let deadline = clock.now + timeout
        while clock.now < deadline {
            if let update = updates.first(where: predicate) {
                return update
            }
            try? await Task.sleep(for: .milliseconds(1))
        }
        return updates.first(where: predicate)
    }
}

private actor Gate {
    private var started = false
    private var releaseContinuation: CheckedContinuation<Void, Never>?
    private var startContinuations: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        started = true
        let continuations = startContinuations
        startContinuations.removeAll()
        continuations.forEach { $0.resume() }
        await withCheckedContinuation { continuation in
            releaseContinuation = continuation
        }
    }

    func waitUntilStarted() async {
        if started {
            return
        }
        await withCheckedContinuation { continuation in
            startContinuations.append(continuation)
        }
    }

    func release() {
        releaseContinuation?.resume()
        releaseContinuation = nil
    }
}

private nonisolated func flickerResult(
    id: String,
    providerID: ProviderID = .apps,
    title: String
) -> SearchResult {
    SearchResult(
        id: id,
        providerID: providerID,
        title: title,
        action: .copyText(title),
        sortHint: 0
    )
}
