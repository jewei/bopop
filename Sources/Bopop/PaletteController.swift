import AppKit
import BopopKit

final class PaletteController: NSObject {
    private static let emptyFileSearchMessage = "Type to search files in your home folder"
    private static let searchingMessage = "Searching…"
    private static let noFileMatchesMessage = "No matches — some locations may require permissions (System Settings → Privacy & Security → Files and Folders / Full Disk Access), or Spotlight indexing may be off"

    private let engine: QueryEngine
    private let actionRunner: ActionRunner
    private let onWillShow: () -> Void
    private let panel: PalettePanel
    private let queryField = NSTextField()
    private let modeChip = PaletteModeChipView()
    private let scrollView = NSScrollView()
    private let tableView = NSTableView()
    private let footerView = PaletteFooterView()
    private let layoutConstraints: PaletteLayout.InstalledConstraints

    private var stickyMode: Mode = .general
    private var results: [SearchResult] = []
    private var selectedIndex = 0
    private var isHiding = false

    init(
        engine: QueryEngine,
        actionRunner: ActionRunner,
        onWillShow: @escaping () -> Void = {}
    ) {
        self.engine = engine
        self.actionRunner = actionRunner
        self.onWillShow = onWillShow
        panel = PalettePanel(
            contentRect: NSRect(
                origin: .zero,
                size: NSSize(
                    width: PaletteMetrics.width,
                    height: Self.panelHeight(resultCount: 0)
                )
            ),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        layoutConstraints = PaletteLayout.install(
            in: panel,
            queryField: queryField,
            modeChip: modeChip,
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

    func show() {
        onWillShow()
        let mouseLocation = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: {
            NSMouseInRect(mouseLocation, $0.frame, false)
        }) ?? NSScreen.main else {
            return
        }

        let visibleFrame = screen.visibleFrame
        let top = visibleFrame.maxY - (visibleFrame.height * 0.25)
        let height = Self.panelHeight(resultCount: results.count)
        let frame = NSRect(
            x: visibleFrame.midX - (PaletteMetrics.width / 2),
            y: top - height,
            width: PaletteMetrics.width,
            height: height
        )
        panel.setFrame(frame, display: true)
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
        panel.orderOut(nil)
        stickyMode = .general
        queryField.stringValue = ""
        results = []
        selectedIndex = 0
        tableView.reloadData()
        scrollView.isHidden = true
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
        actionRunner.onModeChange = { [weak self] mode in
            self?.enterMode(mode)
        }
        actionRunner.hidePalette = { [weak self] in
            self?.hide()
        }
    }

    private func apply(_ update: QueryEngine.Update) {
        results = update.results
        selectedIndex = 0
        tableView.reloadData()
        scrollView.isHidden = results.isEmpty

        if results.isEmpty {
            tableView.deselectAll(nil)
        } else {
            tableView.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
            tableView.scrollRowToVisible(0)
        }
        updateFooter(after: update)
        resizePanel()
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
        }
    }

    private func moveSelection(by offset: Int) {
        guard !results.isEmpty else {
            return
        }
        selectedIndex = min(max(selectedIndex + offset, 0), results.count - 1)
        tableView.selectRowIndexes(
            IndexSet(integer: selectedIndex),
            byExtendingSelection: false
        )
        tableView.scrollRowToVisible(selectedIndex)
        updateFooterActions()
    }

    private func performSelectedCopy() -> Bool {
        if let editor = queryField.currentEditor() as? NSTextView,
           editor.selectedRange().length > 0 {
            return false
        }
        guard results.indices.contains(selectedIndex) else {
            return false
        }
        actionRunner.performCopy(results[selectedIndex])
        return true
    }

    private func resizePanel() {
        let newHeight = Self.panelHeight(resultCount: results.count)
        var frame = panel.frame
        let top = frame.maxY
        frame.origin.y = top - newHeight
        frame.size.height = newHeight
        panel.setFrame(frame, display: true)
    }

    private func updateQuery() {
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
        }
        updateFooterActions()
    }

    private func updateFooterStatus(for query: ParsedQuery) {
        switch query.mode {
        case .general:
            footerView.setStatus("Bopop")
        case .fileSearch:
            footerView.setStatus(
                query.term.isEmpty
                    ? Self.emptyFileSearchMessage
                    : Self.searchingMessage
            )
        case .clipboard:
            footerView.setStatus("Clipboard")
        }
    }

    private func updateFooterActions() {
        guard results.indices.contains(selectedIndex) else {
            footerView.setActions(primary: nil, hasCopy: false)
            return
        }

        let result = results[selectedIndex]
        footerView.setActions(
            primary: Self.actionTitle(for: result.action),
            hasCopy: !Self.isCopyAction(result.action)
                && result.secondaryActions.contains(where: Self.isCopyAction)
        )
    }

    private static func actionTitle(for action: ResultAction) -> String {
        switch action {
        case .openApp, .openFile:
            "Open"
        case .copyText:
            "Copy"
        case .clearClipboardHistory:
            "Clear"
        case .runScript:
            "Run Script"
        case .enterMode:
            "Enter"
        }
    }

    private static func isCopyAction(_ action: ResultAction) -> Bool {
        if case .copyText = action {
            return true
        }
        return false
    }

    private static func panelHeight(resultCount: Int) -> CGFloat {
        let listHeight = resultCount == 0
            ? 0
            : CGFloat(min(resultCount, PaletteMetrics.maxVisibleRows))
                * PaletteMetrics.rowHeight
                + PaletteMetrics.listVerticalPadding * 2
        return PaletteMetrics.fieldHeight
            + PaletteMetrics.separatorHeight
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
            if results.indices.contains(selectedIndex) {
                actionRunner.perform(results[selectedIndex])
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
        return rowView
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        if results.indices.contains(tableView.selectedRow) {
            selectedIndex = tableView.selectedRow
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
