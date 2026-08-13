import Foundation

/// What owns ⏎ right now.
///
/// Replaces the bare `Int` the controller carried, where `-1` meant the hero
/// card. That sentinel had to be spelled correctly at nine write sites and was
/// spelled two ways in one file; `.row(4)` over an empty list is simply not
/// constructible here.
public enum PaletteFocus: Equatable, Sendable {
    case none
    case hero
    case row(Int)

    var rowIndex: Int? {
        guard case let .row(index) = self else {
            return nil
        }
        return index
    }
}

/// Which results surface is on screen. The grid and the table never show
/// together — emoji mode never produces a hero, so a grid presentation always
/// implies no hero card.
public enum PalettePresentation: Equatable, Sendable {
    case list
    case grid
}

public enum PaletteSelectionMove: Equatable, Sendable {
    case up
    case down
    case left
    case right
}

/// Work the adapter must do that isn't drawing.
///
/// Deliberately small. Overlay mechanics, the actions panel and panel geometry
/// stay in the adapter: this module is UI-framework independent and the plan is not a
/// place to accumulate AppKit instructions.
public enum PaletteEffect: Equatable, Sendable {
    /// Hand this query to `QueryEngine`. Already parsed — do not parse again.
    case runQuery(ParsedQuery)
    case closePalette
}

/// Everything the adapter needs to draw one turn, and nothing else.
public struct PaletteRenderPlan: Equatable, Sendable {
    public let queryText: String
    /// The query the rows below answer, parsed exactly once.
    public let query: ParsedQuery
    public let presentation: PalettePresentation
    public let hero: SearchResult?
    public let rows: [SearchResult]
    public let focus: PaletteFocus
    /// False when the drawn content is identical to the previous plan's, so
    /// the adapter can skip `reloadData()` and the panel resize. Selection is
    /// deliberately not part of this: it moves under arrow keys without new
    /// content, so the adapter re-applies focus unconditionally.
    public let contentChanged: Bool
    /// Non-nil when the module changed the query text itself — escape
    /// clearing it, tab autocompleting it, entering a mode. Nil means leave
    /// the field editor alone so typing and the caret are undisturbed.
    public let queryFieldText: String?
    public let effects: [PaletteEffect]

    public var focusedResult: SearchResult? {
        switch focus {
        case .none:
            return nil
        case .hero:
            return hero
        case let .row(index):
            return rows.indices.contains(index) ? rows[index] : nil
        }
    }
}

public struct PaletteStateConfiguration: Equatable, Sendable {
    /// The resting tab row in display order — what ⇥ and ⇧⇥ cycle through.
    /// Transient modes with no pill are omitted, and cycling from one lands on
    /// the first ordered mode.
    public let orderedModes: [Mode]
    /// Tiles per row in the emoji grid. Owned here so vertical moves are
    /// row-major inside the module rather than a `±columns` offset the caller
    /// has to compute.
    public let gridColumns: Int

    public init(orderedModes: [Mode], gridColumns: Int) {
        self.orderedModes = orderedModes
        self.gridColumns = gridColumns
    }
}

/// The palette's Foundation-representable state, in one place.
///
/// The controller used to own the query text, sticky and effective mode,
/// results, hero, selection, restoration id and the last render key as eight
/// separate mutable properties, with six single-caller modules in BopopKit
/// computing fragments of the answer. The arithmetic was unit-tested; the
/// composition — which is where every bug lived — was not testable at all,
/// and the newest test in the repo re-implemented it by hand rather than
/// driving it.
///
/// Every command returns a `PaletteRenderPlan`. The adapter draws the plan and
/// runs its effects; it never reads state back out, and nothing else writes.
@MainActor
public final class PaletteState {
    private let configuration: PaletteStateConfiguration

    private var queryText = ""
    private var stickyMode: Mode = .general
    private var query: ParsedQuery
    private var hero: SearchResult?
    private var rows: [SearchResult] = []
    private var focus: PaletteFocus = .none
    /// Rows may remain on screen while a replacement query is in flight to
    /// avoid a blank frame, but they must not remain executable. True only
    /// after an update answering the current query has been applied.
    private var rowsAnswerCurrentQuery = false
    /// Id of the result the next update should re-select, set by a stay-open
    /// mutation (pin/unpin/hide). Pinning moves the row into or out of the
    /// pinned block, so the default snap back to row 0 would silently retarget
    /// ⏎ at whatever slid into that slot.
    private var restorationID: String?
    private var lastRenderKey: RenderKey?

    public init(configuration: PaletteStateConfiguration) {
        self.configuration = configuration
        query = QueryParser.parse(raw: "", stickyMode: .general)
    }

    public var focusedResult: SearchResult? {
        guard rowsAnswerCurrentQuery else {
            return nil
        }
        return currentPlan(contentChanged: false).focusedResult
    }

    // MARK: - Query and mode

    /// The user typed. Parses once and asks the engine for the result.
    ///
    /// A mode change clears the previous mode's rows immediately rather than
    /// leaving them on screen under the new mode's presentation. Typing `:`
    /// used to flip the presentation to grid while the list's rows were still
    /// loaded, so the panel resized to grid metrics around table rows for one
    /// frame.
    @discardableResult
    public func setQueryText(_ raw: String) -> PaletteRenderPlan {
        setQueryText(raw, echoToField: false)
    }

    /// `echoToField` is set when the module chose the text rather than the
    /// user typing it, so the adapter knows to write it back into the field.
    private func setQueryText(
        _ raw: String,
        echoToField: Bool
    ) -> PaletteRenderPlan {
        queryText = raw
        let parsed = QueryParser.parse(raw: raw, stickyMode: stickyMode)
        let modeChanged = parsed.mode != query.mode
        query = parsed
        rowsAnswerCurrentQuery = false
        if modeChanged {
            clearResults()
        }
        return currentPlan(
            contentChanged: modeChanged,
            queryFieldText: echoToField ? raw : nil,
            effects: [.runQuery(parsed)]
        )
    }

    /// Enters a sticky mode — a tab click, or landing there via ⇥ — clearing
    /// the query text the way the tab row always has.
    @discardableResult
    public func enterMode(_ mode: Mode) -> PaletteRenderPlan {
        stickyMode = mode
        queryText = ""
        query = QueryParser.parse(raw: "", stickyMode: mode)
        clearResults()
        return currentPlan(
            contentChanged: true,
            queryFieldText: "",
            effects: [.runQuery(query)]
        )
    }

    /// Re-runs the current query after a stay-open mutation, remembering which
    /// result ⏎ should still point at.
    @discardableResult
    public func refreshPreservingSelection() -> PaletteRenderPlan {
        restorationID = focusedResult?.id
        return currentPlan(contentChanged: false, effects: [.runQuery(query)])
    }

    // MARK: - Engine

    /// Applies one engine publication.
    ///
    /// An update that answers a different query than the one now current is
    /// ignored. The engine's generation check already drops stale work; this
    /// makes the guarantee structural on the receiving side too, so results
    /// can never be drawn against a query they did not answer.
    @discardableResult
    public func apply(_ update: QueryEngine.Update) -> PaletteRenderPlan {
        guard update.query == query else {
            return currentPlan(contentChanged: false)
        }

        if let top = update.results.first, top.hero != nil {
            hero = top
            rows = Array(update.results.dropFirst())
        } else {
            hero = nil
            rows = update.results
        }
        rowsAnswerCurrentQuery = true

        if let restorationID,
           let restored = rows.firstIndex(where: { $0.id == restorationID }) {
            focus = .row(restored)
        } else if hero != nil {
            focus = .hero
        } else {
            focus = rows.isEmpty ? .none : .row(0)
        }
        // Restoration survives interim updates — the row may only appear in a
        // later one — and is spent on the final update so the next ordinary
        // query starts from row 0 again.
        if update.isFinal {
            restorationID = nil
        }

        let key = RenderKey(hero: hero, rows: rows, presentation: presentation)
        let changed = key != lastRenderKey
        lastRenderKey = key
        return currentPlan(contentChanged: changed)
    }

    // MARK: - Selection

    /// Arrow keys. In list mode ←/→ are not selection moves at all — they
    /// belong to the caret — so they leave focus alone.
    @discardableResult
    public func moveSelection(_ move: PaletteSelectionMove) -> PaletteRenderPlan {
        switch presentation {
        case .grid:
            moveWithinGrid(move)
        case .list:
            moveWithinList(move)
        }
        return currentPlan(contentChanged: false)
    }

    /// A real click. Programmatic selection must never come back through
    /// here — the adapter suppresses its own selection callbacks while it is
    /// applying a plan, so this only ever carries user intent.
    @discardableResult
    public func selectRow(_ index: Int) -> PaletteRenderPlan {
        guard rows.indices.contains(index) else {
            return currentPlan(contentChanged: false)
        }
        focus = .row(index)
        return currentPlan(contentChanged: false)
    }

    @discardableResult
    public func focusHero() -> PaletteRenderPlan {
        if hero != nil {
            focus = .hero
        }
        return currentPlan(contentChanged: false)
    }

    // MARK: - Key policies

    /// ⎋ clears the text, then leaves a sticky mode, then closes the palette.
    @discardableResult
    public func escape() -> PaletteRenderPlan {
        if !queryText.isEmpty {
            return setQueryText("", echoToField: true)
        }
        if stickyMode != .general {
            return enterMode(.general)
        }
        return currentPlan(contentChanged: false, effects: [.closePalette])
    }

    /// ⇥ cycles the tab row — except while a hero that opts in via
    /// `HeroContent.autocompleteText` is showing, where it feeds that text
    /// back into the query so calculation can continue. ⇧⇥ always cycles.
    @discardableResult
    public func tab(shift: Bool) -> PaletteRenderPlan {
        if !shift, let answer = hero?.hero?.autocompleteText {
            return setQueryText(answer, echoToField: true)
        }
        return enterMode(nextMode(offset: shift ? -1 : 1))
    }

    // MARK: - Lifecycle

    /// The palette was dismissed. Everything resets, including the render key
    /// — the adapter empties its views on hide, so the next plan must be
    /// treated as new content even if it happens to match the last one drawn.
    @discardableResult
    public func reset() -> PaletteRenderPlan {
        queryText = ""
        stickyMode = .general
        query = QueryParser.parse(raw: "", stickyMode: .general)
        clearResults()
        restorationID = nil
        lastRenderKey = nil
        return currentPlan(contentChanged: true, queryFieldText: "")
    }

    // MARK: - Implementation

    private var presentation: PalettePresentation {
        query.mode.descriptor.presentation
    }

    /// Readable by the key-routing extension, which lives in another file and
    /// needs it for the one asymmetry in the whole matrix: ←/→ move the
    /// selection in the grid and the caret everywhere else.
    var isGridPresentation: Bool {
        presentation == .grid
    }

    private func clearResults() {
        hero = nil
        rows = []
        focus = .none
        rowsAnswerCurrentQuery = false
        // The adapter draws this empty transition immediately. The next
        // publication must therefore be compared with that empty surface, not
        // with content from before the clear (which can be byte-for-byte equal
        // across two list modes such as General and Apps).
        lastRenderKey = nil
    }

    private func nextMode(offset: Int) -> Mode {
        let modes = configuration.orderedModes
        guard !modes.isEmpty else {
            return query.mode
        }
        // A transient mode with no resting pill has no slot to cycle from, so
        // both directions land on the first ordered mode rather than
        // overshooting from an assumed index 0.
        guard let index = modes.firstIndex(of: query.mode) else {
            return modes[0]
        }
        let count = modes.count
        return modes[((index + offset) % count + count) % count]
    }

    private func moveWithinList(_ move: PaletteSelectionMove) {
        guard move == .up || move == .down else {
            return
        }
        let lowerBound = hero != nil ? -1 : 0
        let upperBound = rows.count - 1
        guard upperBound >= lowerBound else {
            return
        }
        let current: Int
        switch focus {
        case .hero:
            current = -1
        case let .row(index):
            current = index
        case .none:
            current = lowerBound
        }
        let next = min(max(current + (move == .down ? 1 : -1), lowerBound), upperBound)
        focus = next == -1 ? .hero : .row(next)
    }

    /// Row-major, using the configured column count. The old helper took a
    /// `columns` parameter and never read it, so ← from the first tile of a
    /// row wrapped onto the end of the previous row and ↑ from the first row
    /// jumped to tile 0.
    private func moveWithinGrid(_ move: PaletteSelectionMove) {
        let count = rows.count
        let columns = configuration.gridColumns
        guard count > 0, columns > 0 else {
            return
        }
        let current = min(max(focus.rowIndex ?? 0, 0), count - 1)
        let next: Int
        switch move {
        case .left:
            next = current % columns == 0 ? current : current - 1
        case .right:
            next = (current % columns == columns - 1 || current == count - 1)
                ? current
                : current + 1
        case .up:
            next = current < columns ? current : current - columns
        case .down:
            // Snaps into a partial last row rather than refusing to move: a
            // column that doesn't exist down there lands on the last tile.
            next = min(current + columns, count - 1)
        }
        focus = .row(next)
    }

    private func currentPlan(
        contentChanged: Bool,
        queryFieldText: String? = nil,
        effects: [PaletteEffect] = []
    ) -> PaletteRenderPlan {
        PaletteRenderPlan(
            queryText: queryText,
            query: query,
            presentation: presentation,
            hero: hero,
            rows: rows,
            focus: focus,
            contentChanged: contentChanged,
            queryFieldText: queryFieldText,
            effects: effects
        )
    }

    private struct RenderKey: Equatable {
        let hero: SearchResult?
        let rows: [SearchResult]
        let presentation: PalettePresentation
    }
}
