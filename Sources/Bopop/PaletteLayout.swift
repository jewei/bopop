import AppKit

enum PaletteLayout {
    struct InstalledConstraints {
        let generalFieldLeading: NSLayoutConstraint
        let modeFieldLeading: NSLayoutConstraint
    }

    static func install(
        in panel: PalettePanel,
        queryField: NSTextField,
        modeChip: PaletteModeChipView,
        scrollView: NSScrollView,
        tableView: NSTableView,
        footerView: PaletteFooterView
    ) -> InstalledConstraints {
        configurePanel(panel)
        configureQueryField(queryField)
        configureResults(scrollView, tableView: tableView)

        let contentView = PaletteMaterialView()
        contentView.material = .underWindowBackground
        contentView.blendingMode = .behindWindow
        contentView.state = .active

        let searchArea = NSView()
        searchArea.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(searchArea)
        searchArea.addSubview(queryField)
        searchArea.addSubview(modeChip)

        let fieldSeparator = PaletteSeparatorView()
        fieldSeparator.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(fieldSeparator)
        contentView.addSubview(scrollView)
        contentView.addSubview(footerView)

        let generalLeading = queryField.leadingAnchor.constraint(
            equalTo: searchArea.leadingAnchor,
            constant: PaletteMetrics.horizontalInset
        )
        let modeLeading = queryField.leadingAnchor.constraint(
            equalTo: modeChip.trailingAnchor,
            constant: 10
        )

        generalLeading.isActive = true
        NSLayoutConstraint.activate([
            searchArea.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            searchArea.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            searchArea.topAnchor.constraint(equalTo: contentView.topAnchor),
            searchArea.heightAnchor.constraint(equalToConstant: PaletteMetrics.fieldHeight),

            modeChip.leadingAnchor.constraint(
                equalTo: searchArea.leadingAnchor,
                constant: PaletteMetrics.horizontalInset
            ),
            modeChip.centerYAnchor.constraint(equalTo: searchArea.centerYAnchor),
            modeChip.heightAnchor.constraint(equalToConstant: 20),

            queryField.trailingAnchor.constraint(
                equalTo: searchArea.trailingAnchor,
                constant: -PaletteMetrics.horizontalInset
            ),
            queryField.centerYAnchor.constraint(equalTo: searchArea.centerYAnchor),

            fieldSeparator.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            fieldSeparator.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            fieldSeparator.topAnchor.constraint(equalTo: searchArea.bottomAnchor),
            fieldSeparator.heightAnchor.constraint(equalToConstant: PaletteMetrics.separatorHeight),

            scrollView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: fieldSeparator.bottomAnchor),
            scrollView.bottomAnchor.constraint(equalTo: footerView.topAnchor),

            footerView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            footerView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            footerView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            footerView.heightAnchor.constraint(equalToConstant: PaletteMetrics.footerHeight)
        ])

        panel.contentView = contentView
        return InstalledConstraints(
            generalFieldLeading: generalLeading,
            modeFieldLeading: modeLeading
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
        let font = NSFont.systemFont(ofSize: 20, weight: .regular)
        queryField.isEditable = true
        queryField.isBordered = false
        queryField.drawsBackground = false
        queryField.focusRingType = .none
        queryField.font = font
        queryField.textColor = .labelColor
        queryField.placeholderAttributedString = NSAttributedString(
            string: "Search Bopop…",
            attributes: [
                .font: font,
                .foregroundColor: NSColor.secondaryLabelColor
            ]
        )
        queryField.translatesAutoresizingMaskIntoConstraints = false
        queryField.setAccessibilityLabel("Search Bopop")
    }

    private static func configureResults(
        _ scrollView: NSScrollView,
        tableView: NSTableView
    ) {
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("Result"))
        column.resizingMask = .autoresizingMask
        tableView.addTableColumn(column)
        tableView.headerView = nil
        tableView.style = .plain
        tableView.rowHeight = PaletteMetrics.rowHeight
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
        scrollView.scrollerStyle = .overlay
        scrollView.automaticallyAdjustsContentInsets = false
        scrollView.contentInsets = NSEdgeInsets(
            top: PaletteMetrics.listVerticalPadding,
            left: 0,
            bottom: PaletteMetrics.listVerticalPadding,
            right: 0
        )
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.isHidden = true
    }
}

final class PaletteModeChipView: NSView {
    private let label = NSTextField(labelWithString: "")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        configureView()
    }

    required init?(coder: NSCoder) {
        nil
    }

    override var intrinsicContentSize: NSSize {
        NSSize(
            width: label.intrinsicContentSize.width + 16,
            height: 20
        )
    }

    func setTitle(_ title: String) {
        label.stringValue = title
        invalidateIntrinsicContentSize()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateLayerColors()
    }

    private func configureView() {
        wantsLayer = true
        layer?.cornerRadius = 6
        translatesAutoresizingMaskIntoConstraints = false
        isHidden = true
        setContentHuggingPriority(.required, for: .horizontal)
        setContentCompressionResistancePriority(.required, for: .horizontal)

        label.font = .systemFont(ofSize: 11, weight: .semibold)
        label.textColor = .bopopAccent
        label.alignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)

        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            label.topAnchor.constraint(equalTo: topAnchor, constant: 2),
            label.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -2)
        ])
        updateLayerColors()
    }

    private func updateLayerColors() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.backgroundColor = NSColor.bopopAccent
                .withAlphaComponent(0.14)
                .cgColor
        }
    }
}

private final class PaletteMaterialView: NSVisualEffectView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = PaletteMetrics.cornerRadius
        layer?.cornerCurve = .continuous
        layer?.masksToBounds = true
        layer?.borderWidth = PaletteMetrics.separatorHeight
        updateLayerColors()
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateLayerColors()
    }

    private func updateLayerColors() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.borderColor = NSColor.separatorColor.cgColor
        }
    }
}

private final class PaletteSeparatorView: NSView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        updateLayerColors()
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateLayerColors()
    }

    private func updateLayerColors() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.backgroundColor = NSColor.separatorColor.cgColor
        }
    }
}
