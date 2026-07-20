import AppKit
import BopopKit

final class PaletteController: NSObject {
    private static let emptyFileSearchMessage = "Type to search files in your home folder"
    private static let searchingMessage = "Searching…"
    private static let noFileMatchesMessage = "No matches — some locations may require permissions (System Settings → Privacy & Security → Files and Folders / Full Disk Access), or Spotlight indexing may be off, or adjust File Search folders in Settings"

    private let engine: QueryEngine
    private let actionRunner: ActionRunner
    private let onWillShow: () -> Void
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
    private let layoutConstraints: PaletteLayout.InstalledConstraints

    private var stickyMode: Mode = .general
    /// The mode currently reflected by `tabsView`, tracking the EFFECTIVE
    /// mode from the latest engine update — this includes prefix-typed
    /// modes (`f `/`:`/`t `), which drive providers without changing
    /// `stickyMode`. See `apply(_:)`.
    private var lastParsedMode: Mode = .general
    private var results: [SearchResult] = []
    private var heroResult: SearchResult?
    /// -1 means the hero card owns the selection (Return/⌘C act on it); a
    /// valid `results` index means a table row is selected.
    private var selectedIndex = 0
    private var isHiding = false
    private var isProgrammaticFrameChange = false
    private var userAdjustedPosition = false
    private let brandImageURL: URL
    /// Modification date of `brandImageURL` as of the last successful stat,
    /// used to avoid re-decoding the image on every `show()` — only a
    /// changed (or newly missing) date triggers a reload. `nil` means "no
    /// file" (either never checked or confirmed absent).
    private var cachedBrandImageDate: Date?

    init(
        engine: QueryEngine,
        actionRunner: ActionRunner,
        brandImageURL: URL = Storage.production().brandImageURL,
        onWillShow: @escaping () -> Void = {},
        onShowSettings: @escaping () -> Void = {},
        onOpenScriptsFolder: @escaping () -> Void = {},
        onQuit: @escaping () -> Void = {}
    ) {
        self.engine = engine
        self.actionRunner = actionRunner
        self.brandImageURL = brandImageURL
        self.onWillShow = onWillShow
        self.onShowSettings = onShowSettings
        self.onOpenScriptsFolder = onOpenScriptsFolder
        self.onQuit = onQuit
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
        onWillShow()
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
    }

    func hide() {
        guard !isHiding else {
            return
        }

        isHiding = true
        defer { isHiding = false }
        engine.cancel()
        persistPositionIfUserAdjusted()
        panel.orderOut(nil)
        stickyMode = .general
        queryField.stringValue = ""
        results = []
        heroResult = nil
        selectedIndex = 0
        tableView.reloadData()
        gridView.collectionView.reloadData()
        scrollView.isHidden = true
        gridView.isHidden = true
        updateHeroPresentation()
        footerView.setStatus("Bopop")
        footerView.setActions(primary: nil, hasCopy: false)
        lastParsedMode = .general
        tabsView.setActive(.general)
        resizePanel()
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
        panel.onCommandCopy = { [weak self] in
            self?.performSelectedCopy() ?? false
        }
        engine.onUpdate = { [weak self] update in
            self?.apply(update)
        }
        NotificationCenter.default.addObserver(
            forName: NSWindow.didMoveNotification,
            object: panel,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, !self.isProgrammaticFrameChange else {
                    return
                }
                self.userAdjustedPosition = true
            }
        }
        actionRunner.onModeChange = { [weak self] mode in
            self?.enterMode(mode)
        }
        actionRunner.hidePalette = { [weak self] in
            self?.hide()
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
    }

    private func apply(_ update: QueryEngine.Update) {
        let split = HeroPresentation.split(update.results)
        heroResult = split.hero
        results = split.rows
        updateHeroPresentation()

        let query = QueryParser.parse(raw: queryField.stringValue, stickyMode: stickyMode)
        lastParsedMode = query.mode
        tabsView.setActive(query.mode)

        // View swap on the same `results`/`selectedIndex` model: the grid
        // and table never show simultaneously (hero rule untouched — emoji
        // mode never produces one, so `heroResult` is always nil here when
        // `isGridMode` is true).
        let isGrid = isGridMode
        tableView.reloadData()
        gridView.collectionView.reloadData()
        scrollView.isHidden = isGrid || results.isEmpty
        gridView.isHidden = !isGrid || results.isEmpty

        if heroResult != nil {
            // The hero card owns the default selection; the table starts
            // deselected so Return/⌘C activate the hero until the user
            // explicitly arrows down into the row list.
            selectedIndex = -1
            tableView.deselectAll(nil)
            gridView.collectionView.deselectAll(nil)
        } else if results.isEmpty {
            selectedIndex = 0
            tableView.deselectAll(nil)
            gridView.collectionView.deselectAll(nil)
        } else {
            selectedIndex = 0
            if isGrid {
                syncGridSelection()
            } else {
                tableView.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
                tableView.scrollRowToVisible(0)
            }
        }

        updateFooter(after: update, query: query)
        resizePanel()
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

    /// Single click executes the row, launcher-style. Selection state is
    /// already synced by tableViewSelectionDidChange before the action fires.
    @objc private func rowClicked(_ sender: NSTableView) {
        let row = sender.clickedRow
        guard results.indices.contains(row) else {
            return
        }
        selectedIndex = row
        actionRunner.perform(results[row])
    }

    /// Whether the emoji tile grid — rather than the table — is the
    /// currently visible results presentation. Derived from the EFFECTIVE
    /// mode (see `lastParsedMode`'s doc comment), not `stickyMode`, so a
    /// prefix-typed `:term` also renders the grid.
    private var isGridMode: Bool {
        lastParsedMode == .emoji
    }

    /// Mirrors `gridView.collectionView`'s selection to `selectedIndex`
    /// and scrolls the selected tile into view — the grid analog of
    /// `tableView.selectRowIndexes`/`scrollRowToVisible` in
    /// `moveSelection`.
    private func syncGridSelection() {
        guard results.indices.contains(selectedIndex) else {
            gridView.collectionView.deselectAll(nil)
            return
        }
        let indexPath = IndexPath(item: selectedIndex, section: 0)
        gridView.collectionView.selectionIndexPaths = [indexPath]
        // Explicit position: an empty ScrollPosition can no-op in AppKit,
        // leaving the selection below the fold while arrowing.
        gridView.collectionView.scrollToItems(
            at: [indexPath],
            scrollPosition: .nearestHorizontalEdge
        )
    }

    /// Grid analog of `moveSelection(by:)`: ←/→ pass `by: ±1`, ↑/↓ pass
    /// `by: ±PaletteMetrics.gridColumns`. The grid has no hero sentinel
    /// (emoji mode never produces a hero), so this only ever clamps within
    /// `results` via `GridNavigation`.
    private func moveGridSelection(by offset: Int) {
        guard !results.isEmpty else {
            return
        }
        selectedIndex = GridNavigation.move(
            index: max(selectedIndex, 0),
            by: offset,
            columns: PaletteMetrics.gridColumns,
            count: results.count
        )
        syncGridSelection()
        updateFooterActions()
    }

    private func selectedResult() -> SearchResult? {
        if selectedIndex == -1 {
            return heroResult
        }
        guard results.indices.contains(selectedIndex) else {
            return nil
        }
        return results[selectedIndex]
    }

    private func enterMode(_ mode: Mode) {
        stickyMode = mode
        queryField.stringValue = ""
        lastParsedMode = mode
        tabsView.setActive(mode)
        updateQuery()
    }

    /// ⇥ / ⇧⇥ cycles through the ordered tab list from the current
    /// EFFECTIVE mode (not just `stickyMode`, so cycling while a prefix
    /// mode is active continues from that mode).
    private func cycleTab(by offset: Int) {
        let modes = PaletteTabsView.orderedTabs.map(\.0)
        let currentIndex = modes.firstIndex(of: lastParsedMode) ?? 0
        let count = modes.count
        let nextIndex = ((currentIndex + offset) % count + count) % count
        enterMode(modes[nextIndex])
    }

    private func moveSelection(by offset: Int) {
        let lowerBound = heroResult != nil ? -1 : 0
        let upperBound = results.count - 1
        guard upperBound >= lowerBound else {
            return
        }
        selectedIndex = min(max(selectedIndex + offset, lowerBound), upperBound)
        if selectedIndex == -1 {
            tableView.deselectAll(nil)
        } else {
            tableView.selectRowIndexes(
                IndexSet(integer: selectedIndex),
                byExtendingSelection: false
            )
            tableView.scrollRowToVisible(selectedIndex)
        }
        updateFooterActions()
    }

    private func performSelectedCopy() -> Bool {
        if let editor = queryField.currentEditor() as? NSTextView,
           editor.selectedRange().length > 0 {
            return false
        }
        guard let result = selectedResult(), Self.hasCopyAction(result) else {
            return false
        }
        actionRunner.performCopy(result)
        return true
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
        setFrameProgrammatically(frame)
    }

    // MARK: - Dragged-position memory

    private static let positionXKey = "palettePositionTopLeftX"
    private static let positionYKey = "palettePositionTopLeftY"

    private func setFrameProgrammatically(_ frame: NSRect) {
        isProgrammaticFrameChange = true
        defer { isProgrammaticFrameChange = false }
        panel.setFrame(frame, display: true)
    }

    private func persistPositionIfUserAdjusted() {
        guard userAdjustedPosition else {
            return
        }
        let defaults = UserDefaults.standard
        defaults.set(Double(panel.frame.origin.x), forKey: Self.positionXKey)
        defaults.set(Double(panel.frame.maxY), forKey: Self.positionYKey)
    }

    private func savedTopLeft() -> NSPoint? {
        let defaults = UserDefaults.standard
        guard let x = defaults.object(forKey: Self.positionXKey) as? NSNumber,
              let y = defaults.object(forKey: Self.positionYKey) as? NSNumber else {
            return nil
        }
        return NSPoint(x: x.doubleValue, y: y.doubleValue)
    }

    private static func isOnAnyScreen(_ topLeft: NSPoint) -> Bool {
        NSScreen.screens.contains { screen in
            NSMouseInRect(topLeft, screen.visibleFrame, false)
        }
    }

    private func updateQuery() {
        if let editor = queryField.currentEditor() as? NSTextView {
            PaletteLayout.configureFieldEditor(editor)
        }
        let query = QueryParser.parse(
            raw: queryField.stringValue,
            stickyMode: stickyMode
        )
        updateFooterStatus(for: query)
        resizePanel()
        engine.update(raw: queryField.stringValue, stickyMode: stickyMode)
    }

    private func updateFooter(after update: QueryEngine.Update, query: ParsedQuery) {
        switch query.mode {
        case .general:
            footerView.setStatus("Bopop")
        case .apps:
            footerView.setStatus("Apps")
        case .clipboard:
            footerView.setStatus("Clipboard")
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
        case .translation:
            footerView.setStatus("Translate")
        case .snippets:
            footerView.setStatus("Snippets")
        }
        updateFooterActions()
    }

    private func updateFooterStatus(for query: ParsedQuery) {
        switch query.mode {
        case .general:
            footerView.setStatus("Bopop")
        case .apps:
            footerView.setStatus("Apps")
        case .fileSearch:
            footerView.setStatus(
                query.term.isEmpty
                    ? Self.emptyFileSearchMessage
                    : Self.searchingMessage
            )
        case .clipboard:
            footerView.setStatus("Clipboard")
        case .emoji:
            footerView.setStatus("Emoji")
        case .translation:
            footerView.setStatus("Translate")
        case .snippets:
            footerView.setStatus("Snippets")
        }
    }

    private func updateFooterActions() {
        guard let result = selectedResult() else {
            footerView.setActions(primary: nil, hasCopy: false)
            return
        }

        footerView.setActions(
            primary: Self.actionTitle(for: result.action),
            hasCopy: Self.hasCopyAction(result)
        )
    }

    private static func actionTitle(for action: ResultAction) -> String {
        switch action {
        case .openApp, .openFile, .openURL:
            "open"
        case .copyText:
            "copy"
        case .clearClipboardHistory:
            "clear"
        case .runScript:
            "run"
        case .enterMode:
            "select"
        case .downloadTranslation:
            "download"
        case .systemCommand:
            "run"
        }
    }

    private static func hasCopyAction(_ result: SearchResult) -> Bool {
        isCopyAction(result.action)
            || result.secondaryActions.contains(where: isCopyAction)
    }

    private static func isCopyAction(_ action: ResultAction) -> Bool {
        if case .copyText = action {
            return true
        }
        return false
    }

    private static func panelHeight(resultCount: Int, hasHero: Bool, isGrid: Bool) -> CGFloat {
        let contentHeight = isGrid
            ? gridContentHeight(resultCount: resultCount)
            : listContentHeight(resultCount: resultCount)
        let heroHeight: CGFloat = hasHero
            ? PaletteMetrics.heroHeight + PaletteMetrics.listTopInset + PaletteMetrics.listBottomInset
            : 0
        return PaletteMetrics.fieldHeight
            + PaletteMetrics.separatorHeight
            + PaletteMetrics.tabsHeight
            + heroHeight
            + contentHeight
            + PaletteMetrics.footerHeight
    }

    private static func listContentHeight(resultCount: Int) -> CGFloat {
        let visibleRows = min(resultCount, PaletteMetrics.maxVisibleRows)
        guard visibleRows > 0 else {
            return 0
        }
        return CGFloat(visibleRows) * PaletteMetrics.rowHeight
            + CGFloat(visibleRows - 1) * PaletteMetrics.interRowGap
            + PaletteMetrics.listTopInset
            + PaletteMetrics.listBottomInset
    }

    /// 5 tile-rows visible (~300pt content) then scrolls, same
    /// cap-then-scroll pattern as `listContentHeight`'s `maxVisibleRows`.
    private static func gridContentHeight(resultCount: Int) -> CGFloat {
        guard resultCount > 0 else {
            return 0
        }
        let totalRows = (resultCount + PaletteMetrics.gridColumns - 1) / PaletteMetrics.gridColumns
        let visibleRows = min(totalRows, PaletteMetrics.gridVisibleRows)
        return CGFloat(visibleRows) * PaletteMetrics.gridTileSize
            + CGFloat(visibleRows - 1) * PaletteMetrics.gridSpacing
            + PaletteMetrics.listTopInset
            + PaletteMetrics.listBottomInset
    }
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
        switch commandSelector {
        case #selector(NSResponder.moveUp(_:)):
            if isGridMode {
                moveGridSelection(by: -PaletteMetrics.gridColumns)
            } else {
                moveSelection(by: -1)
            }
        case #selector(NSResponder.moveDown(_:)):
            if isGridMode {
                moveGridSelection(by: PaletteMetrics.gridColumns)
            } else {
                moveSelection(by: 1)
            }
        case #selector(NSResponder.moveLeft(_:)):
            // Only meaningful in the grid: in text mode this MUST fall
            // through (return false) so the caret moves normally instead
            // of silently swallowing the keystroke.
            guard isGridMode else {
                return false
            }
            moveGridSelection(by: -1)
        case #selector(NSResponder.moveRight(_:)):
            guard isGridMode else {
                return false
            }
            moveGridSelection(by: 1)
        case #selector(NSResponder.insertTab(_:)):
            cycleTab(by: 1)
        case #selector(NSResponder.insertBacktab(_:)):
            cycleTab(by: -1)
        case #selector(NSResponder.insertNewline(_:)):
            if let result = selectedResult() {
                actionRunner.perform(result)
            }
        case #selector(NSResponder.cancelOperation(_:)):
            switch EscapePolicy.action(
                textIsEmpty: queryField.stringValue.isEmpty,
                stickyMode: stickyMode
            ) {
            case .clearText:
                queryField.stringValue = ""
                updateQuery()
            case .exitMode:
                stickyMode = .general
                lastParsedMode = .general
                tabsView.setActive(.general)
                updateQuery()
            case .closePanel:
                hide()
            }
        default:
            return false
        }
        return true
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
        let rowView = tableView.makeView(
            withIdentifier: ResultRowView.reuseIdentifier,
            owner: self
        ) as? ResultRowView ?? ResultRowView()
        rowView.configure(with: results[row])
        rowView.setSelected(tableView.selectedRow == row)
        return rowView
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        if results.indices.contains(tableView.selectedRow) {
            selectedIndex = tableView.selectedRow
        } else if tableView.selectedRow == -1, heroResult != nil {
            selectedIndex = -1
        }
        updateFooterActions()
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
        guard let indexPath = indexPaths.first, results.indices.contains(indexPath.item) else {
            return
        }
        selectedIndex = indexPath.item
        actionRunner.perform(results[indexPath.item])
    }
}
