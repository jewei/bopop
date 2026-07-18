import AppKit

enum PaletteLayout {
    struct InstalledConstraints {
        let generalFieldLeading: NSLayoutConstraint
        let modeFieldLeading: NSLayoutConstraint
        let resultsBottom: NSLayoutConstraint
    }

    static func install(
        in panel: PalettePanel,
        queryField: NSTextField,
        modeChip: NSTextField,
        scrollView: NSScrollView,
        tableView: NSTableView
    ) -> InstalledConstraints {
        configurePanel(panel)
        configureQueryField(queryField)
        configureModeChip(modeChip)
        configureResults(scrollView, tableView: tableView)

        let contentView = NSVisualEffectView()
        contentView.material = .popover
        contentView.blendingMode = .behindWindow
        contentView.state = .active
        contentView.wantsLayer = true
        contentView.layer?.cornerRadius = 12
        contentView.layer?.masksToBounds = true

        let searchArea = NSView()
        searchArea.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(searchArea)
        searchArea.addSubview(queryField)
        searchArea.addSubview(modeChip)
        contentView.addSubview(scrollView)

        let generalLeading = queryField.leadingAnchor.constraint(
            equalTo: searchArea.leadingAnchor,
            constant: 16
        )
        let modeLeading = queryField.leadingAnchor.constraint(
            equalTo: modeChip.trailingAnchor,
            constant: 10
        )
        let resultsBottom = scrollView.bottomAnchor.constraint(
            equalTo: contentView.bottomAnchor
        )

        generalLeading.isActive = true
        NSLayoutConstraint.activate([
            searchArea.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            searchArea.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            searchArea.topAnchor.constraint(equalTo: contentView.topAnchor),
            searchArea.heightAnchor.constraint(equalToConstant: 60),

            modeChip.leadingAnchor.constraint(equalTo: searchArea.leadingAnchor, constant: 16),
            modeChip.centerYAnchor.constraint(equalTo: searchArea.centerYAnchor),
            modeChip.widthAnchor.constraint(equalToConstant: 76),
            modeChip.heightAnchor.constraint(equalToConstant: 24),

            queryField.trailingAnchor.constraint(equalTo: searchArea.trailingAnchor, constant: -16),
            queryField.centerYAnchor.constraint(equalTo: searchArea.centerYAnchor),

            scrollView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: searchArea.bottomAnchor),
            resultsBottom
        ])

        panel.contentView = contentView
        return InstalledConstraints(
            generalFieldLeading: generalLeading,
            modeFieldLeading: modeLeading,
            resultsBottom: resultsBottom
        )
    }

    private static func configurePanel(_ panel: PalettePanel) {
        panel.level = .statusBar
        panel.collectionBehavior = [
            .canJoinAllSpaces,
            .fullScreenAuxiliary,
            .transient,
            .ignoresCycle
        ]
        panel.isFloatingPanel = true
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.animationBehavior = .none
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
    }

    private static func configureQueryField(_ queryField: NSTextField) {
        queryField.isEditable = true
        queryField.isBordered = false
        queryField.drawsBackground = false
        queryField.focusRingType = .none
        queryField.font = .systemFont(ofSize: 22)
        queryField.placeholderString = "Search"
        queryField.translatesAutoresizingMaskIntoConstraints = false
    }

    private static func configureModeChip(_ modeChip: NSTextField) {
        modeChip.isBordered = false
        modeChip.drawsBackground = false
        modeChip.isEditable = false
        modeChip.isSelectable = false
        modeChip.alignment = .center
        modeChip.font = .systemFont(ofSize: 11, weight: .medium)
        modeChip.textColor = .secondaryLabelColor
        modeChip.wantsLayer = true
        modeChip.layer?.backgroundColor = NSColor.quaternaryLabelColor.cgColor
        modeChip.layer?.cornerRadius = 12
        modeChip.translatesAutoresizingMaskIntoConstraints = false
        modeChip.isHidden = true
    }

    private static func configureResults(
        _ scrollView: NSScrollView,
        tableView: NSTableView
    ) {
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("Result"))
        column.resizingMask = .autoresizingMask
        tableView.addTableColumn(column)
        tableView.headerView = nil
        tableView.rowHeight = 48
        tableView.intercellSpacing = .zero
        tableView.selectionHighlightStyle = .regular
        tableView.allowsEmptySelection = false
        tableView.allowsMultipleSelection = false
        tableView.backgroundColor = .clear

        scrollView.documentView = tableView
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.isHidden = true
    }
}
