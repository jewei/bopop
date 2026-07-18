import AppKit
import BopopKit

final class PaletteController: NSObject {
    private static let panelWidth: CGFloat = 640
    private static let searchHeight: CGFloat = 60
    private static let rowHeight: CGFloat = 48
    private static let maximumVisibleRows = 9
    private static let resultsBottomPadding: CGFloat = 8

    private let engine: QueryEngine
    private let actionRunner: ActionRunner
    private let panel: PalettePanel
    private let queryField = NSTextField()
    private let modeChip = NSTextField(labelWithString: "")
    private let scrollView = NSScrollView()
    private let tableView = NSTableView()
    private let layoutConstraints: PaletteLayout.InstalledConstraints

    private var stickyMode: Mode = .general
    private var results: [SearchResult] = []
    private var selectedIndex = 0
    private var isHiding = false

    init(engine: QueryEngine, actionRunner: ActionRunner) {
        self.engine = engine
        self.actionRunner = actionRunner
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
            tableView: tableView
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
        engine.update(raw: queryField.stringValue, stickyMode: stickyMode)
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
        resizePanel()
    }

    private func enterMode(_ mode: Mode) {
        stickyMode = mode
        queryField.stringValue = ""
        updateModeChip()
        engine.update(raw: "", stickyMode: stickyMode)
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
        let newHeight = Self.searchHeight
            + CGFloat(visibleRows) * Self.rowHeight
            + bottomPadding
        var frame = panel.frame
        let top = frame.maxY
        frame.origin.y = top - newHeight
        frame.size.height = newHeight
        panel.setFrame(frame, display: true)
    }
}

extension PaletteController: NSTextFieldDelegate {
    func controlTextDidChange(_ notification: Notification) {
        engine.update(raw: queryField.stringValue, stickyMode: stickyMode)
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
                engine.update(raw: "", stickyMode: stickyMode)
            case .exitMode:
                stickyMode = .general
                updateModeChip()
                engine.update(raw: "", stickyMode: stickyMode)
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
