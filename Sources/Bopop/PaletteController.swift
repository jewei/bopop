import AppKit
import BopopKit

final class PaletteController: NSObject {
    private static let emptyFileSearchMessage = "Type to search files in your home folder"
    private static let searchingMessage = "Searching…"
    private static let noFileMatchesMessage = "No matches — some locations may require permissions (System Settings → Privacy & Security → Files and Folders / Full Disk Access), or Spotlight indexing may be off"

    private let engine: QueryEngine
    private let actionRunner: ActionRunner
    private let onWillShow: () -> Void
    private let onShowSettings: () -> Void
    private let onOpenScriptsFolder: () -> Void
    private let onQuit: () -> Void
    private let panel: PalettePanel
    private let queryField = NSTextField()
    private let brandView = PaletteBrandView()
    private let modeChip = PaletteModeChipView()
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
    private let footerView = PaletteFooterView()
    private let layoutConstraints: PaletteLayout.InstalledConstraints

    private var stickyMode: Mode = .general
    private var results: [SearchResult] = []
    private var heroResult: SearchResult?
    /// -1 means the hero card owns the selection (Return/⌘C act on it); a
    /// valid `results` index means a table row is selected.
    private var selectedIndex = 0
    private var isHiding = false
    private var isProgrammaticFrameChange = false
    private var userAdjustedPosition = false

    init(
        engine: QueryEngine,
        actionRunner: ActionRunner,
        onWillShow: @escaping () -> Void = {},
        onShowSettings: @escaping () -> Void = {},
        onOpenScriptsFolder: @escaping () -> Void = {},
        onQuit: @escaping () -> Void = {}
    ) {
        self.engine = engine
        self.actionRunner = actionRunner
        self.onWillShow = onWillShow
        self.onShowSettings = onShowSettings
        self.onOpenScriptsFolder = onOpenScriptsFolder
        self.onQuit = onQuit
        panel = PalettePanel(
            contentRect: NSRect(
                origin: .zero,
                size: NSSize(
                    width: PaletteMetrics.width,
                    height: Self.panelHeight(resultCount: 0, hasHero: false)
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
            modeChip: modeChip,
            escapeKeycap: escapeKeycap,
            heroView: heroView,
            scrollView: scrollView,
            tableView: tableView,
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
        let height = Self.panelHeight(resultCount: results.count, hasHero: heroResult != nil)
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
        scrollView.isHidden = true
        updateHeroPresentation()
        footerView.setStatus("Bopop")
        footerView.setActions(primary: nil, hasCopy: false)
        updateModeChip()
        resizePanel()
    }

    private func connectCallbacks() {
        queryField.delegate = self
        tableView.dataSource = self
        tableView.delegate = self

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
        tableView.reloadData()
        scrollView.isHidden = results.isEmpty

        if heroResult != nil {
            // The hero card owns the default selection; the table starts
            // deselected so Return/⌘C activate the hero until the user
            // explicitly arrows down into the row list.
            selectedIndex = -1
            tableView.deselectAll(nil)
        } else if results.isEmpty {
            selectedIndex = 0
            tableView.deselectAll(nil)
        } else {
            selectedIndex = 0
            tableView.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
            tableView.scrollRowToVisible(0)
        }
        updateFooter(after: update)
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
        updateModeChip()
        updateQuery()
    }

    private func updateModeChip() {
        switch stickyMode {
        case .general:
            modeChip.isHidden = true
            layoutConstraints.modeFieldLeading.isActive = false
            layoutConstraints.generalFieldLeading.isActive = true
        case .apps:
            modeChip.setTitle("Apps")
            modeChip.isHidden = false
            layoutConstraints.generalFieldLeading.isActive = false
            layoutConstraints.modeFieldLeading.isActive = true
        case .fileSearch:
            modeChip.setTitle("Files")
            modeChip.isHidden = false
            layoutConstraints.generalFieldLeading.isActive = false
            layoutConstraints.modeFieldLeading.isActive = true
        case .clipboard:
            modeChip.setTitle("Clipboard")
            modeChip.isHidden = false
            layoutConstraints.generalFieldLeading.isActive = false
            layoutConstraints.modeFieldLeading.isActive = true
        case .emoji:
            modeChip.setTitle("Emoji")
            modeChip.isHidden = false
            layoutConstraints.generalFieldLeading.isActive = false
            layoutConstraints.modeFieldLeading.isActive = true
        case .translation:
            modeChip.setTitle("Translate")
            modeChip.isHidden = false
            layoutConstraints.generalFieldLeading.isActive = false
            layoutConstraints.modeFieldLeading.isActive = true
        }
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
        let newHeight = Self.panelHeight(resultCount: results.count, hasHero: heroResult != nil)
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

    private func updateFooter(after update: QueryEngine.Update) {
        let query = QueryParser.parse(
            raw: queryField.stringValue,
            stickyMode: stickyMode
        )
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
            footerView.setStatus("Emoji")
        case .translation:
            footerView.setStatus("Translate")
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

    private static func panelHeight(resultCount: Int, hasHero: Bool) -> CGFloat {
        let visibleRows = min(resultCount, PaletteMetrics.maxVisibleRows)
        let listHeight: CGFloat
        if visibleRows == 0 {
            listHeight = 0
        } else {
            listHeight = CGFloat(visibleRows) * PaletteMetrics.rowHeight
                + CGFloat(visibleRows - 1) * PaletteMetrics.interRowGap
                + PaletteMetrics.listTopInset
                + PaletteMetrics.listBottomInset
        }
        let heroHeight: CGFloat = hasHero
            ? PaletteMetrics.heroHeight + PaletteMetrics.listTopInset + PaletteMetrics.listBottomInset
            : 0
        return PaletteMetrics.fieldHeight
            + PaletteMetrics.separatorHeight
            + heroHeight
            + listHeight
            + PaletteMetrics.footerHeight
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
            moveSelection(by: -1)
        case #selector(NSResponder.moveDown(_:)):
            moveSelection(by: 1)
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
                updateModeChip()
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
