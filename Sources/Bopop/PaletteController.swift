import AppKit
import BopopKit
import Quartz

final class PaletteController: NSObject {
    private static let emptyFileSearchMessage = "Type to search files in your home folder"
    private static let searchingMessage = "Searching…"
    private static let noFileMatchesMessage = "No matches — some locations may require permissions (System Settings → Privacy & Security → Files and Folders / Full Disk Access), or Spotlight indexing may be off, or adjust File Search folders in Settings"

    private let engine: QueryEngine
    private let actionRunner: ActionRunner
    private let refreshAppsOnShow: () async -> Bool
    private let onShowSettings: () -> Void
    private let onOpenScriptsFolder: () -> Void
    private let onQuit: () -> Void
    private let panel: PalettePanel
    private let queryField = NSTextField()
    private let brandView = PaletteBrandView()
    private let tabsView = PaletteTabsView()
    private let escapeKeycap = PaletteKeycapView(
        text: "esc",
        fontSize: 11,
        textAlpha: 0.40,
        horizontalPadding: 8,
        verticalPadding: 3
    )
    private let heroView = PaletteHeroView()
    private let scrollView = NSScrollView()
    private let tableView = NSTableView()
    private let gridView = EmojiGridView()
    private let footerView = PaletteFooterView()
    private let largeTypeController = LargeTypeWindowController()
    private let actionsPanel = ActionsPanelController()
    private let layoutConstraints: PaletteLayout.InstalledConstraints

    /// The palette's state. Sole authority for query text, mode, results,
    /// hero and selection — this controller is its AppKit adapter and never
    /// writes any of that itself.
    private let state: PaletteState
    /// The plan currently on screen, so the table and grid data sources have
    /// something to read. Replaced wholesale by every plan and never consulted
    /// to decide what happens next; `state` decides.
    private var rendered: PaletteRenderPlan
    /// Set while `commit` drives AppKit's selection. `selectRowIndexes` fires
    /// `tableViewSelectionDidChange` synchronously, and without this the
    /// delegate would write the selection back as if the user had moved it —
    /// two authorities inside one call stack. Same idiom as
    /// `isProgrammaticFrameChange`.
    private var isApplyingPlan = false
    /// Draws that began while another was still in progress. Must stay zero: a
    /// re-entrant draw runs against half-updated views, and one of them hung
    /// the app outright. Counted rather than asserted so a test can pin it.
    private var reentrantDrawCount = 0
    /// Completed dismissals. Observable without a screen, unlike
    /// `panel.isVisible`: `show()` bails when no screen owns the palette, so a
    /// headless test host can never see the panel become visible.
    private var hideCount = 0
    private var appRefreshTask: Task<Void, Never>?
    private var isHiding = false
    private var isProgrammaticFrameChange = false
    private var userAdjustedPosition = false
    /// Registered once, lazily, the first time Quick Look is shown.
    /// `QLPreviewPanel` is a system singleton we can't subclass, so unlike
    /// `PalettePanel`/`LargeTypePanel` there's no `resignKey` override to
    /// hook — `NSWindow.didResignKeyNotification` is the equivalent signal.
    /// See `observeQuickLookResign`.
    private var quickLookResignObserver: NotificationToken?
    private var panelMoveObserver: NotificationToken?
    private let brandImageURL: URL
    private let defaults: UserDefaults
    /// Modification date of `brandImageURL` as of the last successful stat,
    /// used to avoid re-decoding the image on every `show()` — only a
    /// changed (or newly missing) date triggers a reload. `nil` means "no
    /// file" (either never checked or confirmed absent).
    private var cachedBrandImageDate: Date?

    init(
        engine: QueryEngine,
        actionRunner: ActionRunner,
        // No production defaults: a test that forgot to override `defaults`
        // would have `persistPositionIfUserAdjusted` write the palette's
        // position into the developer's real standard defaults, and would read
        // the real brand image back out. `AppDelegate` is the single wiring
        // point and already passes both, so requiring them costs nothing.
        brandImageURL: URL,
        defaults: UserDefaults,
        refreshAppsOnShow: @escaping () async -> Bool = { false },
        onShowSettings: @escaping () -> Void = {},
        onOpenScriptsFolder: @escaping () -> Void = {},
        onQuit: @escaping () -> Void = {}
    ) {
        self.engine = engine
        self.actionRunner = actionRunner
        self.brandImageURL = brandImageURL
        self.defaults = defaults
        self.refreshAppsOnShow = refreshAppsOnShow
        self.onShowSettings = onShowSettings
        self.onOpenScriptsFolder = onOpenScriptsFolder
        self.onQuit = onQuit
        let state = PaletteState(
            configuration: PaletteStateConfiguration(
                orderedModes: PaletteTabsView.orderedTabs.map(\.0),
                gridColumns: PaletteMetrics.gridColumns
            )
        )
        self.state = state
        rendered = state.reset()
        panel = PalettePanel(
            contentRect: NSRect(
                origin: .zero,
                size: NSSize(
                    width: PaletteMetrics.width,
                    height: Self.panelHeight(resultCount: 0, hasHero: false, isGrid: false)
                )
            ),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        layoutConstraints = PaletteLayout.install(
            in: panel,
            queryField: queryField,
            brandView: brandView,
            escapeKeycap: escapeKeycap,
            tabsView: tabsView,
            heroView: heroView,
            scrollView: scrollView,
            tableView: tableView,
            gridView: gridView,
            footerView: footerView
        )
        super.init()
        connectCallbacks()
    }

    func toggle() {
        if panel.isVisible && panel.isKeyWindow {
            hide()
        } else {
            show()
        }
    }

    /// Idempotent: shows the palette if hidden; no-op if already visible
    /// and key. Relied on by `applicationShouldHandleReopen` as a failsafe
    /// for a broken/unregistered hotkey — relaunching (or reopening) the
    /// app must always be able to surface the palette.
    func show() {
        guard !(panel.isVisible && panel.isKeyWindow) else {
            return
        }
        PerformanceSignposts.palette.interval("Palette Show") {
            showMeasured()
        }
    }

    private func showMeasured() {
        refreshBrandImage()
        let height = Self.panelHeight(
            resultCount: results.count,
            hasHero: heroResult != nil,
            isGrid: isGridMode
        )
        let frame: NSRect
        if let topLeft = savedTopLeft(), Self.isOnAnyScreen(topLeft) {
            frame = NSRect(
                x: topLeft.x,
                y: topLeft.y - height,
                width: PaletteMetrics.width,
                height: height
            )
        } else {
            let mouseLocation = NSEvent.mouseLocation
            guard let screen = NSScreen.screens.first(where: {
                NSMouseInRect(mouseLocation, $0.frame, false)
            }) ?? NSScreen.main else {
                return
            }
            let visibleFrame = screen.visibleFrame
            let top = visibleFrame.maxY - (visibleFrame.height * 0.25)
            frame = NSRect(
                x: visibleFrame.midX - (PaletteMetrics.width / 2),
                y: top - height,
                width: PaletteMetrics.width,
                height: height
            )
        }
        setFrameProgrammatically(frame)
        panel.makeKeyAndOrderFront(nil)
        panel.makeFirstResponder(queryField)
        updateQuery()
        refreshAppsAfterShowing()
    }

    func hide() {
        guard !isHiding else {
            return
        }

        isHiding = true
        hideCount += 1
        defer { isHiding = false }
        appRefreshTask?.cancel()
        appRefreshTask = nil
        actionsPanel.hide()
        engine.cancel()
        persistPositionIfUserAdjusted()
        if QLPreviewPanel.sharedPreviewPanelExists() {
            QLPreviewPanel.shared().orderOut(nil)
        }
        largeTypeController.hide()
        panel.orderOut(nil)
        // Resets the whole state set, including the render key: the views are
        // emptied below, so identical content next time must still redraw.
        rendered = state.reset()
        queryField.stringValue = ""
        tableView.reloadData()
        gridView.collectionView.reloadData()
        scrollView.isHidden = true
        gridView.isHidden = true
        updateHeroPresentation()
        footerView.setStatus("Bopop")
        footerView.setActions(primary: nil, hasActions: false)
        tabsView.setActive(rendered.query.mode)
        resizePanel()
    }

    private func refreshAppsAfterShowing() {
        appRefreshTask?.cancel()
        let refreshAppsOnShow = refreshAppsOnShow
        appRefreshTask = Task { [weak self] in
            guard !Task.isCancelled else {
                return
            }
            let changed = await refreshAppsOnShow()
            guard let self,
                  changed,
                  !Task.isCancelled,
                  panel.isVisible else {
                return
            }
            let mode = rendered.query.mode
            guard mode == .general || mode == .apps else {
                return
            }
            updateQueryPreservingSelection()
        }
    }

    /// Cheap stat-and-compare: only decodes `brandImageURL` when its
    /// modification date has changed since the last check (including the
    /// transition to/from "file missing"), so a Settings-driven import or
    /// reset applies on the next summon without restart, per design doc.
    /// Missing/undecodable file silently falls back to the keycap.
    private func refreshBrandImage() {
        let attributes = try? FileManager.default.attributesOfItem(atPath: brandImageURL.path)
        let modificationDate = attributes?[.modificationDate] as? Date
        guard modificationDate != cachedBrandImageDate else {
            return
        }
        cachedBrandImageDate = modificationDate
        guard modificationDate != nil, let image = NSImage(contentsOf: brandImageURL) else {
            brandView.setCustomImage(nil)
            return
        }
        brandView.setCustomImage(image)
    }

    private func connectCallbacks() {
        queryField.delegate = self
        tableView.dataSource = self
        tableView.delegate = self
        tableView.target = self
        tableView.action = #selector(rowClicked(_:))
        gridView.collectionView.dataSource = self
        gridView.collectionView.delegate = self

        panel.onResign = { [weak self] in self?.hide() }
        // One callback for every chord. Which key means what — including the
        // panel-only gating and the overlay-dismiss precedence — is
        // `PaletteState.route`'s decision, not seven closures' worth of
        // duplicated conditions.
        panel.onKey = { [weak self] key in
            self?.handle(key) ?? false
        }
        actionsPanel.onRun = { [weak self] kind in
            self?.runAction(kind)
        }
        panel.quickLookDataSource = self
        panel.quickLookDelegate = self
        largeTypeController.onDismiss = { [weak self] in
            guard let self else { return }
            largeTypeController.hide()
            // Explicitly hand key back to the palette rather than relying on
            // AppKit to pick a successor window on its own — this is what
            // lets LargeTypePanel.resignKey's deferred keyWindow check tell
            // "overlay dismissed, palette regains key" apart from "user
            // switched to another app" (see onFocusLost below).
            panel.makeKeyAndOrderFront(nil)
        }
        largeTypeController.onFocusLost = { [weak self] in
            self?.hide()
        }
        engine.onUpdate = { [weak self] update in
            self?.apply(update)
        }
        panelMoveObserver = NotificationToken(
            name: NSWindow.didMoveNotification,
            object: panel
        ) { [weak self] in
            guard let self, !isProgrammaticFrameChange else {
                return
            }
            userAdjustedPosition = true
        }
        actionRunner.onModeChange = { [weak self] mode in
            self?.enterMode(mode)
        }
        actionRunner.hidePalette = { [weak self] in
            self?.hide()
        }
        actionRunner.onStayOpenRefresh = { [weak self] in
            self?.updateQueryPreservingSelection()
        }
        tabsView.onSelect = { [weak self] mode in
            self?.enterMode(mode)
        }
        footerView.onShowSettings = { [weak self] in
            self?.hide()
            self?.onShowSettings()
        }
        footerView.onOpenScriptsFolder = { [weak self] in
            self?.hide()
            self?.onOpenScriptsFolder()
        }
        footerView.onQuit = { [weak self] in
            self?.onQuit()
        }
        footerView.onShowActions = { [weak self] in
            _ = self?.toggleActionsPanel()
        }
    }

    // Read-only views onto the plan currently drawn. The controller reads
    // these; only `state` produces them.
    private var results: [SearchResult] { rendered.rows }
    private var heroResult: SearchResult? { rendered.hero }

    private func apply(_ update: QueryEngine.Update) {
        PerformanceSignposts.palette.interval("Results Apply") {
            commit(state.apply(update), after: update)
        }
    }

    /// Draws one plan and runs its effects. The single place AppKit is told
    /// anything about results, mode or selection.
    private func commit(
        _ plan: PaletteRenderPlan,
        after update: QueryEngine.Update? = nil
    ) {
        actionsPanel.hide()
        rendered = plan

        if let text = plan.queryFieldText, queryField.stringValue != text {
            queryField.stringValue = text
            if let editor = queryField.currentEditor() {
                editor.selectedRange = NSRange(location: text.count, length: 0)
            }
        }
        if let editor = queryField.currentEditor() as? NSTextView {
            PaletteLayout.configureFieldEditor(editor)
        }

        if isApplyingPlan {
            reentrantDrawCount += 1
        }
        // Covers the whole draw, not just the selection call. `reloadData()`
        // changes the table's selection and fires
        // `tableViewSelectionDidChange` synchronously, so a guard around
        // `applyFocus` alone let the delegate mistake our own reload for a
        // user click and re-enter `commit` — against views that were only
        // half updated. In emoji mode the re-entrant pass reached
        // `syncGridSelection` while the collection view still held the
        // previous mode's items but its data source already reported the new
        // count, and AppKit wedged there. That hung the MainActor's executor,
        // so every later engine update was silently never delivered.
        isApplyingPlan = true

        tabsView.setActive(plan.query.mode)
        updateQueryFieldAccessibility(for: plan.query.mode)
        updateHeroPresentation()

        let isGrid = plan.presentation == .grid
        if plan.contentChanged {
            tableView.reloadData()
            gridView.collectionView.reloadData()
        }
        scrollView.isHidden = isGrid || plan.rows.isEmpty
        gridView.isHidden = !isGrid || plan.rows.isEmpty
        applyFocus(plan.focus, isGrid: isGrid)

        if let update {
            updateFooter(after: update, query: plan.query)
        } else {
            updateFooterStatus(for: plan.query)
            updateFooterActions()
        }
        if plan.contentChanged {
            resizePanel()
        }

        // Cleared before the effects run: they are not drawing, and one of
        // them can re-enter through `hide()`.
        isApplyingPlan = false

        for effect in plan.effects {
            switch effect {
            case let .runQuery(query):
                engine.update(query: query)
            case .closePalette:
                hide()
            }
        }
    }

    /// Drives AppKit's selection from the plan. Runs inside `commit`'s
    /// `isApplyingPlan` guard, which owns the flag — clearing it here would
    /// reopen the write-back path for the rest of the draw.
    private func applyFocus(_ focus: PaletteFocus, isGrid: Bool) {
        switch focus {
        case .none, .hero:
            tableView.deselectAll(nil)
            gridView.collectionView.deselectAll(nil)
        case let .row(index):
            if isGrid {
                syncGridSelection(to: index)
            } else {
                tableView.selectRowIndexes(
                    IndexSet(integer: index),
                    byExtendingSelection: false
                )
                tableView.scrollRowToVisible(index)
            }
        }
    }

    private func updateHeroPresentation() {
        let hasHero = heroResult != nil
        heroView.isHidden = !hasHero
        layoutConstraints.scrollTopToHero.isActive = hasHero
        layoutConstraints.scrollTopToSeparator.isActive = !hasHero
        if let hero = heroResult?.hero {
            heroView.configure(with: hero)
        }
    }

    /// Single click executes the row, launcher-style. The click carries its
    /// own index rather than reading back whatever AppKit selected, so the
    /// action can never fire against a different row than the one hit.
    @objc private func rowClicked(_ sender: NSTableView) {
        let row = sender.clickedRow
        guard results.indices.contains(row) else {
            return
        }
        commit(state.selectRow(row))
        if let result = selectedResult() {
            actionRunner.perform(result)
        }
    }

    /// Whether the emoji tile grid — rather than the table — is the currently
    /// visible results presentation. Driven by the plan, so it reflects the
    /// EFFECTIVE mode (a prefix-typed `:term` renders the grid too) and can
    /// never disagree with the rows actually loaded.
    private var isGridMode: Bool {
        rendered.presentation == .grid
    }

    /// Mirrors the plan's focus into `gridView.collectionView` and scrolls the
    /// tile into view — the grid analog of
    /// `tableView.selectRowIndexes`/`scrollRowToVisible`.
    private func syncGridSelection(to index: Int) {
        // Checked against the collection view's own count, not just the plan's:
        // selecting or scrolling to an item the view does not hold yet wedges
        // AppKit outright rather than failing, and the view lags the plan
        // whenever a draw is still in progress.
        guard results.indices.contains(index),
              index < gridView.collectionView.numberOfItems(inSection: 0) else {
            gridView.collectionView.deselectAll(nil)
            return
        }
        let indexPath = IndexPath(item: index, section: 0)
        gridView.collectionView.selectionIndexPaths = [indexPath]
        // Explicit position: an empty ScrollPosition can no-op in AppKit,
        // leaving the selection below the fold while arrowing.
        gridView.collectionView.scrollToItems(
            at: [indexPath],
            scrollPosition: .nearestHorizontalEdge
        )
    }

    private func selectedResult() -> SearchResult? {
        state.focusedResult
    }

    private func enterMode(_ mode: Mode) {
        commit(state.enterMode(mode))
    }

    /// The tab row shows which mode is active; VoiceOver users get that
    /// context from the field's label instead, since the pills are decoration
    /// as far as the query field is concerned.
    private func updateQueryFieldAccessibility(for mode: Mode) {
        let tabs = PaletteTabsView.orderedTabs + PaletteTabsView.transientTabs
        guard let title = tabs.first(where: { $0.0 == mode })?.1 else {
            return
        }
        queryField.setAccessibilityLabel(
            mode == .general ? "Search Bopop" : "Search \(title)"
        )
    }

    private func performSelectedReveal() -> Bool {
        guard let path = FilePayload.path(for: selectedResult()) else {
            return false
        }
        actionRunner.performReveal(path)
        return true
    }

    /// No-op (returns `false`, letting the key event fall through
    /// harmlessly) when the selection has no file path and the panel isn't
    /// already open to be dismissed.
    private func toggleQuickLook() -> Bool {
        if QLPreviewPanel.sharedPreviewPanelExists(), QLPreviewPanel.shared().isVisible {
            QLPreviewPanel.shared().orderOut(nil)
            // See largeTypeController.onDismiss above: explicitly re-key the
            // palette rather than relying on AppKit's successor-window
            // choice, so the deferred check in observeQuickLookResign can
            // tell this apart from a genuine app switch.
            panel.makeKeyAndOrderFront(nil)
            return true
        }
        guard FilePayload.path(for: selectedResult()) != nil else {
            return false
        }
        let qlPanel = QLPreviewPanel.shared()!
        observeQuickLookResign(qlPanel)
        qlPanel.makeKeyAndOrderFront(nil)
        return true
    }

    /// `QLPreviewPanel` is a private AppKit subclass handed out by
    /// `.shared()` — it can't be subclassed to override `resignKey` the way
    /// `PalettePanel`/`LargeTypePanel` do, so `NSWindow.didResignKeyNotification`
    /// is the equivalent hook. The singleton outlives any single preview
    /// session, so the observer is registered once for this controller's lifetime.
    ///
    /// Mirrors the same deferred one-runloop-turn keyWindow check as
    /// `PalettePanel.resignKey`/`LargeTypePanel.resignKey`: the successor
    /// key window isn't settled yet at notification time, so wait a turn,
    /// then only treat it as a genuine focus loss (hide the whole palette)
    /// if that successor isn't one of the app's own panels.
    private func observeQuickLookResign(_ qlPanel: QLPreviewPanel) {
        guard quickLookResignObserver == nil else {
            return
        }
        quickLookResignObserver = NotificationToken(
            name: NSWindow.didResignKeyNotification,
            object: qlPanel
        ) { [weak self] in
            guard let self else { return }
            FocusLossCheck.runDeferred(ownPanel: panel) { [weak self] in
                self?.hide()
            }
        }
    }

    /// No-op (returns `false`) when the selection has no large-type text
    /// representation and the panel isn't already open to be dismissed.
    private func toggleLargeType() -> Bool {
        if largeTypeController.isVisible {
            largeTypeController.hide()
            return true
        }
        // `selectedResult()` already returns the hero whenever focus is
        // `.hero`, and an update with a hero always takes focus — so a
        // fallback to the hero here can never fire and was dead code.
        // `panel.screen` is nil whenever the frame intersects no screen (a
        // saved position after a display change — the case `show()` guards
        // with `isOnAnyScreen`), and `NSScreen.main` is nil when no screen
        // owns the key window. Bail like `show()` does rather than trap.
        guard let text = LargeType.text(for: selectedResult()),
              let screen = panel.screen ?? NSScreen.main else {
            return false
        }
        largeTypeController.show(text: text, on: screen)
        return true
    }

    /// No-op (returns `false`) when nothing is selected — matching the
    /// hidden footer button in that state.
    private func toggleActionsPanel() -> Bool {
        if actionsPanel.isVisible {
            actionsPanel.hide()
            return true
        }
        return presentActionsPanel()
    }

    /// Show semantics rather than toggle: a right-click on a row should open
    /// the panel for THAT row, never close a panel that's already up for a
    /// different one.
    @discardableResult
    private func presentActionsPanel() -> Bool {
        actionsPanel.hide()
        guard let result = selectedResult() else {
            return false
        }
        actionsPanel.show(
            items: ResultActions.items(for: result),
            title: result.title,
            over: panel
        )
        return true
    }

    /// Every panel exit runs through here: close first, then dispatch to
    /// the same paths the shortcuts used pre-panel, so Quick Look/Large
    /// Type toggle their overlays with the panel already gone.
    private func runAction(_ kind: ResultActions.Kind) {
        actionsPanel.hide()
        switch kind {
        case .primary:
            if let result = selectedResult() {
                actionRunner.perform(result)
            }
        case .copy:
            // The panel's Copy is an explicit action on the result — the
            // field-editor-selection veto in performSelectedCopy exists to
            // disambiguate a bare ⌘C, which can't reach here.
            if let result = selectedResult(), ResultActions.hasCopyAction(result) {
                actionRunner.performCopy(result)
            }
        case .pin:
            if let result = selectedResult(), ResultActions.hasPinAction(result) {
                actionRunner.performPin(result)
            }
        case .quit:
            if let result = selectedResult() {
                actionRunner.performQuit(result)
            }
        case .hide:
            if let result = selectedResult() {
                actionRunner.performHide(result)
            }
        case .reveal:
            _ = performSelectedReveal()
        case .quickLook:
            _ = toggleQuickLook()
        case .largeType:
            _ = toggleLargeType()
        }
    }

    private func refreshQuickLookIfVisible() {
        guard QLPreviewPanel.sharedPreviewPanelExists(), QLPreviewPanel.shared().isVisible else {
            return
        }
        // A selection change that lands on a result with no file path (e.g.
        // arrowing onto a clipboard-text row) has nothing for Quick Look to
        // show — `reloadData` would just leave the previous preview's
        // content stuck on screen. Close the panel instead of showing stale
        // (or blank) content for an item that was never previewable.
        guard FilePayload.path(for: selectedResult()) != nil else {
            QLPreviewPanel.shared().orderOut(nil)
            return
        }
        QLPreviewPanel.shared().reloadData()
    }

    private func resizePanel() {
        let newHeight = Self.panelHeight(
            resultCount: results.count,
            hasHero: heroResult != nil,
            isGrid: isGridMode
        )
        var frame = panel.frame
        let top = frame.maxY
        frame.origin.y = top - newHeight
        frame.size.height = newHeight
        // A bottom-saved/dragged position plus a tall result set can grow the
        // frame below the screen's visible area (under the Dock or off the
        // bottom entirely). Shift the whole frame up to fit — never resize
        // the content — rather than let it clip.
        if let visibleFrame = panel.screen?.visibleFrame {
            frame.origin.y = max(frame.origin.y, visibleFrame.minY)
        }
        setFrameProgrammatically(frame)
    }

    /// Thin conversion over `PaletteGeometry`, which works in `Double` to
    /// keep CoreGraphics out of BopopKit.
    private static func panelHeight(
        resultCount: Int,
        hasHero: Bool,
        isGrid: Bool
    ) -> CGFloat {
        CGFloat(
            PaletteMetrics.geometry.panelHeight(
                resultCount: resultCount,
                hasHero: hasHero,
                isGrid: isGrid
            )
        )
    }

    // MARK: - Dragged-position memory

    private func setFrameProgrammatically(_ frame: NSRect) {
        isProgrammaticFrameChange = true
        defer { isProgrammaticFrameChange = false }
        panel.setFrame(frame, display: true)
    }

    private func persistPositionIfUserAdjusted() {
        guard userAdjustedPosition else {
            return
        }
        defaults.set(
            Double(panel.frame.origin.x),
            for: PersistedPreferenceKeys.palettePositionX
        )
        defaults.set(
            Double(panel.frame.maxY),
            for: PersistedPreferenceKeys.palettePositionY
        )
    }

    private func savedTopLeft() -> NSPoint? {
        guard let x = defaults.number(for: PersistedPreferenceKeys.palettePositionX),
              let y = defaults.number(for: PersistedPreferenceKeys.palettePositionY) else {
            return nil
        }
        return NSPoint(x: x.doubleValue, y: y.doubleValue)
    }

    private static func isOnAnyScreen(_ topLeft: NSPoint) -> Bool {
        NSScreen.screens.contains { screen in
            NSMouseInRect(topLeft, screen.visibleFrame, false)
        }
    }

    /// Stay-open mutations (pin/unpin/hide) re-run the query but keep ⏎ on the
    /// row that was just acted on, even though pinning moves it.
    private func updateQueryPreservingSelection() {
        commit(state.refreshPreservingSelection())
    }

    private func updateQuery() {
        commit(state.setQueryText(queryField.stringValue))
    }

    private func updateFooter(after update: QueryEngine.Update, query: ParsedQuery) {
        switch query.mode {
        case .fileSearch:
            if query.term.isEmpty {
                footerView.setStatus(Self.emptyFileSearchMessage)
            } else if !update.isFinal {
                footerView.setStatus(Self.searchingMessage)
            } else if update.results.isEmpty {
                footerView.setStatus(Self.noFileMatchesMessage)
            } else {
                footerView.setStatus("Files")
            }
        case .emoji:
            // Emoji mode has no hero, so `results` == `update.results` here
            // — count with grouping ("1,914 emoji" / "12 matches"), noun
            // driven by whether there's a search term narrowing the catalog.
            let noun = query.term.isEmpty ? "emoji" : "matches"
            footerView.setStatus("\(results.count.formatted()) \(noun)")
        default:
            footerView.setStatus(Self.footerLabel(for: query.mode))
        }
        updateFooterActions()
    }

    private func updateFooterStatus(for query: ParsedQuery) {
        switch query.mode {
        case .fileSearch:
            footerView.setStatus(
                query.term.isEmpty
                    ? Self.emptyFileSearchMessage
                    : Self.searchingMessage
            )
        default:
            footerView.setStatus(Self.footerLabel(for: query.mode))
        }
    }

    /// The static Mode→label mapping shared by `updateFooter` and
    /// `updateFooterStatus` — both diverge only for `.fileSearch` (progress
    /// states) and, in `updateFooter`'s case, `.emoji` (live result count),
    /// which each keep as an explicit case above instead of going through
    /// this helper.
    private static func footerLabel(for mode: Mode) -> String {
        switch mode {
        case .general: "Bopop"
        case .apps: "Apps"
        case .fileSearch: "Files"
        case .clipboard: "Clipboard"
        case .emoji: "Emoji"
        case .translation: "Translate"
        case .snippets: "Snippets"
        }
    }

    private func updateFooterActions() {
        guard let result = selectedResult() else {
            footerView.setActions(primary: nil, hasActions: false)
            return
        }

        footerView.setActions(
            primary: ResultActions.verb(for: result.action),
            hasActions: true
        )
    }

    /// The one place a key is dispatched. Both input paths — `NSEvent` chords
    /// via `PalettePanel.performKeyEquivalent` and `NSResponder` selectors via
    /// `doCommandBy` — decode to a `PaletteKey` and arrive here.
    ///
    /// Returns whether the key was handled. `false` is load-bearing: it lets
    /// AppKit carry on, which is how ←/→ move the caret and ⌘C copies selected
    /// text out of the query field.
    @discardableResult
    private func handle(_ key: PaletteKey) -> Bool {
        let overlays = PaletteOverlays(
            actionsPanelIsVisible: actionsPanel.isVisible,
            quickLookIsVisible: QLPreviewPanel.sharedPreviewPanelExists()
                && QLPreviewPanel.shared().isVisible,
            largeTypeIsVisible: largeTypeController.isVisible
        )
        switch state.route(key, overlays: overlays) {
        case .passThrough:
            return false
        case let .perform(action):
            return perform(action)
        }
    }

    private func perform(_ action: PaletteKeyAction) -> Bool {
        switch action {
        case let .moveSelection(move):
            commit(state.moveSelection(move))
            refreshQuickLookIfVisible()
        case let .cycleTab(shift):
            commit(state.tab(shift: shift))
        case .runFocused:
            guard let result = selectedResult() else {
                break
            }
            actionRunner.perform(result)
        case .escape:
            commit(state.escape())
        case let .actionsPanelMove(offset):
            actionsPanel.moveSelection(by: offset)
        case .actionsPanelRunSelected:
            actionsPanel.runSelected()
        case .actionsPanelDismiss:
            actionsPanel.hide()
        case let .actionsPanelRun(kind):
            // The module already confirmed the panel offers this action, so a
            // false here would mean the two disagree.
            return actionsPanel.run(kind: kind)
        case .toggleActionsPanel:
            return toggleActionsPanel()
        case .toggleQuickLook:
            return toggleQuickLook()
        case .toggleLargeType:
            return toggleLargeType()
        case .showSettings:
            hide()
            onShowSettings()
        case .closePalette:
            hide()
        case .swallow:
            break
        }
        return true
    }
}

// MARK: - Test surface
//
// Until now nothing could construct a PaletteController, let alone drive one,
// so ~3,660 lines of the palette cluster had no way to be tested and a
// re-entrancy hang in `commit` shipped and had to be found by hand against a
// running app. These are the minimum needed to stand one up and poke it the
// way AppKit does. Same idiom as `MessageHUDController.panelForTesting`.
extension PaletteController {
    /// Draws that began while another was still in progress. Zero is the
    /// invariant; anything else means a delegate callback re-entered `commit`.
    var reentrantDrawCountForTesting: Int { reentrantDrawCount }
    var renderedPlanForTesting: PaletteRenderPlan { rendered }
    var tableRowCountForTesting: Int { tableView.numberOfRows }
    var gridItemCountForTesting: Int {
        gridView.collectionView.numberOfItems(inSection: 0)
    }
    var isTableVisibleForTesting: Bool { !scrollView.isHidden }
    var isGridVisibleForTesting: Bool { !gridView.isHidden }
    var selectedTableRowForTesting: Int { tableView.selectedRow }

    /// Types into the query field exactly as AppKit does: set the value, then
    /// fire the delegate. Going through the notification rather than calling
    /// `updateQuery` keeps the real path — including the delegate hop that
    /// produced the re-entrancy — under test.
    func typeForTesting(_ text: String) {
        queryField.stringValue = text
        controlTextDidChange(
            Notification(
                name: NSControl.textDidChangeNotification,
                object: queryField
            )
        )
    }

    func enterModeForTesting(_ mode: Mode) {
        enterMode(mode)
    }

    /// Dispatches a key through the real path — route, then perform — and
    /// reports whether it was handled.
    @discardableResult
    func handleKeyForTesting(_ key: PaletteKey) -> Bool {
        handle(key)
    }

    var queryTextForTesting: String { rendered.queryText }
    var isPanelVisibleForTesting: Bool { panel.isVisible }
    var hideCountForTesting: Int { hideCount }
}

extension PaletteController: NSTextFieldDelegate {
    func controlTextDidChange(_ notification: Notification) {
        updateQuery()
    }

    func control(
        _ control: NSControl,
        textView: NSTextView,
        doCommandBy commandSelector: Selector
    ) -> Bool {
        guard let key = Self.paletteKey(for: commandSelector) else {
            return false
        }
        return handle(key)
    }

    /// Decodes an `NSResponder` selector into a semantic key. Pure glue —
    /// what the key then means is `PaletteState.route`'s decision.
    private static func paletteKey(for selector: Selector) -> PaletteKey? {
        switch selector {
        case #selector(NSResponder.moveUp(_:)): return .up
        case #selector(NSResponder.moveDown(_:)): return .down
        case #selector(NSResponder.moveLeft(_:)): return .left
        case #selector(NSResponder.moveRight(_:)): return .right
        case #selector(NSResponder.insertTab(_:)): return .tab
        case #selector(NSResponder.insertBacktab(_:)): return .backTab
        case #selector(NSResponder.insertNewline(_:)): return .enter
        case #selector(NSResponder.cancelOperation(_:)): return .escape
        default: return nil
        }
    }
}

extension PaletteController: NSTableViewDataSource, NSTableViewDelegate {
    func numberOfRows(in tableView: NSTableView) -> Int {
        results.count
    }

    func tableView(
        _ tableView: NSTableView,
        viewFor tableColumn: NSTableColumn?,
        row: Int
    ) -> NSView? {
        guard results.indices.contains(row) else {
            return nil
        }
        let rowView = tableView.makeView(
            withIdentifier: ResultRowView.reuseIdentifier,
            owner: self
        ) as? ResultRowView ?? ResultRowView()
        rowView.configure(with: results[row])
        rowView.setSelected(tableView.selectedRow == row)
        rowView.onRightClick = { [weak self] in
            guard let self, results.indices.contains(row) else {
                return
            }
            commit(state.selectRow(row))
            presentActionsPanel()
        }
        return rowView
    }

    /// Reports a selection the USER made. Programmatic selection is filtered
    /// out by `isApplyingPlan`: `commit` drives `selectRowIndexes`, which fires
    /// this synchronously, and letting it write back would make AppKit a second
    /// authority racing the one inside the same call stack.
    func tableViewSelectionDidChange(_ notification: Notification) {
        guard !isApplyingPlan else {
            return
        }
        if results.indices.contains(tableView.selectedRow) {
            commit(state.selectRow(tableView.selectedRow))
        }
        updateFooterActions()
        refreshQuickLookIfVisible()
    }

    func tableView(
        _ tableView: NSTableView,
        rowViewForRow row: Int
    ) -> NSTableRowView? {
        PaletteRowView()
    }
}

extension PaletteController: NSCollectionViewDataSource, NSCollectionViewDelegate {
    func collectionView(_ collectionView: NSCollectionView, numberOfItemsInSection section: Int) -> Int {
        results.count
    }

    func collectionView(
        _ collectionView: NSCollectionView,
        itemForRepresentedObjectAt indexPath: IndexPath
    ) -> NSCollectionViewItem {
        let item = collectionView.makeItem(
            withIdentifier: EmojiTileItem.reuseIdentifier,
            for: indexPath
        ) as? EmojiTileItem ?? EmojiTileItem()
        guard results.indices.contains(indexPath.item) else {
            return item
        }
        item.configure(with: results[indexPath.item])
        return item
    }

    /// Single click performs the tile's result, mirroring `rowClicked`'s
    /// launcher-style single-click-executes behavior for the table.
    /// `collectionView.selectionIndexPaths` is already updated by AppKit
    /// before this delegate call fires.
    func collectionView(_ collectionView: NSCollectionView, didSelectItemsAt indexPaths: Set<IndexPath>) {
        guard !isApplyingPlan,
              let indexPath = indexPaths.first,
              results.indices.contains(indexPath.item) else {
            return
        }
        commit(state.selectRow(indexPath.item))
        if let result = selectedResult() {
            actionRunner.perform(result)
        }
    }
}

extension PaletteController: QLPreviewPanelDataSource, QLPreviewPanelDelegate {
    func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int {
        FilePayload.path(for: selectedResult()) != nil ? 1 : 0
    }

    /// Quick Look is key while visible, so ⌘Y never reaches `PalettePanel` —
    /// the second press that is supposed to dismiss it has to be caught here.
    /// `LargeTypePanel` solves the same problem by overriding
    /// `performKeyEquivalent`, which is not available for a system singleton
    /// that cannot be subclassed; this delegate hook is its equivalent.
    ///
    /// Escape already worked because Quick Look handles that itself.
    func previewPanel(_ panel: QLPreviewPanel!, handle event: NSEvent!) -> Bool {
        guard event?.type == .keyDown,
              event.relevantModifiers == .command,
              event.charactersIgnoringModifiers?.lowercased() == "y" else {
            return false
        }
        return handle(.commandQuickLook)
    }

    func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> QLPreviewItem! {
        guard let path = FilePayload.path(for: selectedResult()) else {
            return nil
        }
        return URL(fileURLWithPath: path) as QLPreviewItem
    }
}
