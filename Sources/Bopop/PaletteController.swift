import AppKit
import BopopKit

final class PaletteController: NSObject {
    private static let panelWidth: CGFloat = 640
    private static let searchHeight: CGFloat = 60
    private static let rowHeight: CGFloat = 48
    private static let maximumVisibleRows = 9
    private static let resultsBottomPadding: CGFloat = 8
    private static let footerHeight: CGFloat = 24
    private static let emptyFileSearchMessage = "Type to search files in your home folder"
    private static let searchingMessage = "Searching…"
    private static let noFileMatchesMessage = "No matches — some locations may require permissions (System Settings → Privacy & Security → Files and Folders / Full Disk Access), or Spotlight indexing may be off"

    private let engine: QueryEngine
    private let actionRunner: ActionRunner
    private let onWillShow: () -> Void
    private let panel: PalettePanel
    private let queryField = NSTextField()
    private let modeChip = NSTextField(labelWithString: "")
    private let scrollView = NSScrollView()
    private let tableView = NSTableView()
    private let footerLabel = NSTextField(labelWithString: "")
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
                size: NSSize(width: Self.panelWidth, height: Self.searchHeight)
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
            footerLabel: footerLabel
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
        let frame = NSRect(
            x: visibleFrame.midX - (Self.panelWidth / 2),
            y: top - Self.searchHeight,
            width: Self.panelWidth,
            height: Self.searchHeight
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
        layoutConstraints.resultsBottom.constant = 0
        setFooter(nil)
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
        layoutConstraints.resultsBottom.constant = results.isEmpty
            ? 0
            : -Self.resultsBottomPadding

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
            modeChip.stringValue = "Files"
            modeChip.isHidden = false
            layoutConstraints.generalFieldLeading.isActive = false
            layoutConstraints.modeFieldLeading.isActive = true
        case .clipboard:
            modeChip.stringValue = "Clipboard"
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
        let visibleRows = min(results.count, Self.maximumVisibleRows)
        let bottomPadding = results.isEmpty ? 0 : Self.resultsBottomPadding
        let footerHeight = footerLabel.isHidden ? 0 : Self.footerHeight
        let newHeight = Self.searchHeight
            + CGFloat(visibleRows) * Self.rowHeight
            + bottomPadding
            + footerHeight
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
        if query.mode == .fileSearch {
            setFooter(
                query.term.isEmpty
                    ? Self.emptyFileSearchMessage
                    : Self.searchingMessage
            )
        } else {
            setFooter(nil)
        }
        resizePanel()
        engine.update(raw: queryField.stringValue, stickyMode: stickyMode)
    }

    private func updateFooter(after update: QueryEngine.Update) {
        let query = QueryParser.parse(
            raw: queryField.stringValue,
            stickyMode: stickyMode
        )
        guard query.mode == .fileSearch else {
            setFooter(nil)
            return
        }
        guard !query.term.isEmpty else {
            setFooter(Self.emptyFileSearchMessage)
            return
        }
        guard update.isFinal else {
            setFooter(Self.searchingMessage)
            return
        }
        setFooter(update.results.isEmpty ? Self.noFileMatchesMessage : nil)
    }

    private func setFooter(_ message: String?) {
        footerLabel.stringValue = message ?? ""
        footerLabel.toolTip = message
        footerLabel.isHidden = message == nil
        layoutConstraints.footerHeight.constant = message == nil
            ? 0
            : Self.footerHeight
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
    }
}
