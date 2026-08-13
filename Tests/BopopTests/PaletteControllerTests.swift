import AppKit
import Foundation
import Testing
@testable import Bopop
@testable import BopopKit

// The first tests that stand up a PaletteController.
//
// The palette cluster had no way to be constructed from a test, so its ~3,660
// lines were verified by hand. These drive the real controller, with real
// AppKit views, through the real engine, and cover the wiring: typing reaches
// the engine, results reach the table, the grid and table swap correctly, and
// focus lands where the plan says.
//
// What they do NOT cover is the AppKit re-entrancy that hung the app — an
// off-screen table does not fire its selection delegate from `reloadData()`,
// so the path simply is not live here. Reverting the fix leaves this file
// green. Closing that gap needs a UI test host, which the project does not
// have.

@MainActor
private func makeController(
    results: @escaping @Sendable (ParsedQuery) -> [SearchResult]
) throws -> (controller: PaletteController, root: URL) {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let provider = StubProvider(results: results)
    let engine = QueryEngine(
        providers: [
            .general: [provider],
            .apps: [provider],
            .clipboard: [provider],
            .emoji: [provider]
        ],
        debounce: [:],
        settle: .zero
    )
    // A UUID-named suite, never `.standard`: the palette persists its dragged
    // position, and a test must not write that into the developer's defaults.
    let defaults = try #require(UserDefaults(suiteName: UUID().uuidString))
    let controller = PaletteController(
        engine: engine,
        actionRunner: ActionRunner(
            storage: Storage(baseDirectory: root),
            clipboardStore: ClipboardStore(storage: Storage(baseDirectory: root)),
            visibilityStore: VisibilityStore(storage: Storage(baseDirectory: root)),
            scriptFeedback: ScriptFeedback(storage: Storage(baseDirectory: root))
        ),
        brandImageURL: root.appendingPathComponent("brand.png"),
        preferences: PreferencesRepository(defaults: defaults)
    )
    return (controller, root)
}

/// Waits for the controller's drawn plan to satisfy `predicate`. Polling, not
/// sleeping — these tests are about what gets drawn, not how fast.
@MainActor
private func wait(
    on controller: PaletteController,
    timeout: Duration = .seconds(10),
    for predicate: (PaletteRenderPlan) -> Bool
) async throws {
    let clock = ContinuousClock()
    let deadline = clock.now + timeout
    while clock.now < deadline, !predicate(controller.renderedPlanForTesting) {
        try? await Task.sleep(for: .milliseconds(1))
    }
    guard predicate(controller.renderedPlanForTesting) else {
        throw PaletteControllerTestTimeout()
    }
}

private struct PaletteControllerTestTimeout: Error {}

@MainActor
@Test
func typingDrawsTheResultsIntoTheTable() async throws {
    let (controller, root) = try makeController { query in
        query.term.isEmpty ? [] : (0..<3).map { row("hit\($0)", matching: query.term) }
    }
    defer { try? FileManager.default.removeItem(at: root) }

    controller.typeForTesting("saf")
    try await wait(on: controller) { !$0.rows.isEmpty }

    #expect(controller.renderedPlanForTesting.rows.count == 3)
    #expect(controller.tableRowCountForTesting == 3)
    #expect(controller.isTableVisibleForTesting)
    #expect(!controller.isGridVisibleForTesting)
}

/// Guards the invariant behind the hang: a draw must never begin while another
/// is in progress.
///
/// Honest limitation — this does NOT reproduce the original bug. Reverting the
/// fix leaves it green, because an off-screen `NSTableView` does not fire
/// `tableViewSelectionDidChange` from `reloadData()` the way a real one does,
/// and the collection view does not wedge. It is a cheap standing check on the
/// invariant, not proof the defect is caught. What still has no test is the
/// AppKit re-entrancy itself.
@MainActor
@Test
func drawingResultsNeverReEntersTheDraw() async throws {
    let (controller, root) = try makeController { query in
        query.term.isEmpty
            ? []
            : (0..<(query.term.count == 1 ? 25 : 12)).map {
                row("hit\($0)", matching: query.term)
            }
    }
    defer { try? FileManager.default.removeItem(at: root) }

    controller.typeForTesting("a")
    try await wait(on: controller) { $0.rows.count == 25 }
    controller.typeForTesting("ab")
    try await wait(on: controller) { $0.rows.count == 12 }

    #expect(controller.reentrantDrawCountForTesting == 0)
}

/// The exact sequence that hung: a mode publishing a large result set into the
/// collection view, then leaving it. The engine must still be delivering
/// afterwards — when this hung, the MainActor executor was dead and every
/// later query silently returned nothing.
@MainActor
@Test
func leavingAGridModeKeepsTheEngineDelivering() async throws {
    let (controller, root) = try makeController { query in
        query.mode == .emoji
            ? (0..<1914).map { row("emoji\($0)") }
            : (query.term.isEmpty ? [] : [row("app:safari", matching: query.term)])
    }
    defer { try? FileManager.default.removeItem(at: root) }

    controller.enterModeForTesting(.emoji)
    try await wait(on: controller) { $0.rows.count == 1914 }
    #expect(controller.isGridVisibleForTesting)
    #expect(controller.gridItemCountForTesting == 1914)

    controller.enterModeForTesting(.apps)
    controller.typeForTesting("saf")
    try await wait(on: controller) { $0.rows.count == 1 }

    #expect(controller.renderedPlanForTesting.rows.map(\.id) == ["app:safari"])
    #expect(controller.tableRowCountForTesting == 1)
    #expect(controller.isTableVisibleForTesting)
    #expect(!controller.isGridVisibleForTesting)
    #expect(controller.reentrantDrawCountForTesting == 0)
}

/// CLAUDE.md: selection is an index into the rows, and the palette must not
/// let AppKit's own selection callbacks author it.
@MainActor
@Test
func programmaticSelectionDoesNotComeBackAsUserInput() async throws {
    let (controller, root) = try makeController { query in
        query.term.isEmpty ? [] : (0..<5).map { row("hit\($0)", matching: query.term) }
    }
    defer { try? FileManager.default.removeItem(at: root) }

    controller.typeForTesting("a")
    try await wait(on: controller) { $0.rows.count == 5 }

    #expect(controller.renderedPlanForTesting.focus == .row(0))
    #expect(controller.selectedTableRowForTesting == 0)
    #expect(controller.reentrantDrawCountForTesting == 0)
}

@MainActor
@Test
func aSynchronousNestedDrawIsQueuedUntilTheOuterDrawCompletes() async throws {
    let (controller, root) = try makeController { query in
        query.term.isEmpty ? [] : (0..<3).map { row("hit\($0)", matching: query.term) }
    }
    defer { try? FileManager.default.removeItem(at: root) }

    controller.typeForTesting("a")
    try await wait(on: controller) { $0.rows.count == 3 }

    controller.reenterNextDrawForTesting(with: .down)
    #expect(controller.handleKeyForTesting(.down))

    #expect(controller.reentrantDrawCountForTesting == 1, "the injected callback re-entered")
    #expect(controller.renderedPlanForTesting.focus == .row(2), "the queued newer plan wins")
    #expect(controller.selectedTableRowForTesting == 2)
}

// MARK: - Fixtures

/// Titles have to contain the term: `Ranker` filters non-matching candidates,
/// so a fixture titled "hit0" would be dropped before it ever reached a view
/// and the test would be asserting on the ranker, not the palette.
private nonisolated func row(_ id: String, matching term: String = "") -> SearchResult {
    SearchResult(
        id: id,
        providerID: .apps,
        title: term.isEmpty ? id : "\(term) \(id)",
        action: .copyText(id),
        sortHint: 0
    )
}

private nonisolated final class StubProvider: ResultProvider {
    let id: ProviderID = .apps
    private let make: @Sendable (ParsedQuery) -> [SearchResult]

    init(results: @escaping @Sendable (ParsedQuery) -> [SearchResult]) {
        make = results
    }

    func results(for query: ParsedQuery) async throws -> [SearchResult] {
        make(query)
    }
}

// MARK: - Key dispatch

/// The adapter half of key routing: `PaletteState.route` decides, and these
/// check the controller actually performs the decision.

@MainActor
@Test
func escapeClearsTheQueryFieldThenClosesThePalette() async throws {
    let (controller, root) = try makeController { query in
        query.term.isEmpty ? [] : [row("hit", matching: query.term)]
    }
    defer { try? FileManager.default.removeItem(at: root) }

    controller.typeForTesting("saf")
    try await wait(on: controller) { !$0.rows.isEmpty }

    // Counted rather than reading `panel.isVisible`: `show()` bails when no
    // screen owns the palette, so a headless CI host never sees it visible.
    #expect(controller.handleKeyForTesting(.escape))
    #expect(controller.queryTextForTesting.isEmpty)
    #expect(controller.hideCountForTesting == 0, "first escape only clears")

    #expect(controller.handleKeyForTesting(.escape))
    #expect(controller.hideCountForTesting == 1, "second escape closes")
}

@MainActor
@Test
func tabCyclesTheModeThroughTheAdapter() async throws {
    let (controller, root) = try makeController { _ in [] }
    defer { try? FileManager.default.removeItem(at: root) }

    let before = controller.renderedPlanForTesting.query.mode
    #expect(controller.handleKeyForTesting(.tab))
    #expect(controller.renderedPlanForTesting.query.mode != before)
}

/// `false` is the load-bearing outcome: it lets AppKit move the caret instead
/// of the keystroke being silently swallowed.
@MainActor
@Test
func horizontalArrowsAreReportedUnhandledInListMode() async throws {
    let (controller, root) = try makeController { query in
        query.term.isEmpty ? [] : (0..<3).map { row("hit\($0)", matching: query.term) }
    }
    defer { try? FileManager.default.removeItem(at: root) }

    controller.typeForTesting("a")
    try await wait(on: controller) { $0.rows.count == 3 }

    #expect(!controller.handleKeyForTesting(.left))
    #expect(!controller.handleKeyForTesting(.right))
    #expect(controller.handleKeyForTesting(.down), "but vertical arrows are ours")
    #expect(controller.renderedPlanForTesting.focus == .row(1))
}

@MainActor
@Test
func commandCloseHidesThePalette() async throws {
    let (controller, root) = try makeController { _ in [] }
    defer { try? FileManager.default.removeItem(at: root) }

    #expect(controller.handleKeyForTesting(.commandClose))
    #expect(controller.hideCountForTesting == 1)
    #expect(controller.handleKeyForTesting(.commandClose))
    #expect(controller.hideCountForTesting == 1, "dismissal is idempotent within one session")
}
