import AppKit
import QuartzCore

enum PaletteLayout {
    struct InstalledConstraints {
        /// List top anchor when no hero card is showing. Was pinned to the
        /// field hairline directly; now pinned to the (always-visible)
        /// tabs row's bottom edge instead — name kept for continuity with
        /// the existing toggle pattern in `PaletteController`.
        let scrollTopToSeparator: NSLayoutConstraint
        let scrollTopToHero: NSLayoutConstraint
    }

    private static let queryFont = NSFont.systemFont(ofSize: 34, weight: .heavy)
    private static let queryKern = -0.68

    private static var queryTextAttributes: [NSAttributedString.Key: Any] {
        [
            .font: queryFont,
            .foregroundColor: NSColor.white,
            .kern: queryKern
        ]
    }

    static func install(
        in panel: PalettePanel,
        queryField: NSTextField,
        brandView: PaletteBrandView,
        escapeKeycap: PaletteKeycapView,
        tabsView: PaletteTabsView,
        heroView: PaletteHeroView,
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
        // Layer cornerRadius clips the CONTENT but not the blur material —
        // the visual-effect region needs its own rounded mask, otherwise a
        // faint square material edge ghosts around the corners.
        contentView.maskImage = roundedCornerMask(radius: PaletteMetrics.cornerRadius)

        let tintView = PaletteTintView()
        tintView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(tintView)

        let searchArea = NSView()
        searchArea.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(searchArea)
        searchArea.addSubview(brandView)
        searchArea.addSubview(queryField)
        searchArea.addSubview(escapeKeycap)

        let fieldSeparator = PaletteSeparatorView()
        fieldSeparator.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(fieldSeparator)
        contentView.addSubview(tabsView)
        heroView.isHidden = true
        contentView.addSubview(heroView)
        contentView.addSubview(scrollView)
        contentView.addSubview(footerView)

        NSLayoutConstraint.activate([
            tintView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            tintView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            tintView.topAnchor.constraint(equalTo: contentView.topAnchor),
            tintView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),

            searchArea.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            searchArea.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            searchArea.topAnchor.constraint(equalTo: contentView.topAnchor),
            searchArea.heightAnchor.constraint(equalToConstant: PaletteMetrics.fieldHeight),

            brandView.leadingAnchor.constraint(
                equalTo: searchArea.leadingAnchor,
                constant: PaletteMetrics.headerInset
            ),
            brandView.centerYAnchor.constraint(equalTo: searchArea.centerYAnchor),
            brandView.widthAnchor.constraint(equalToConstant: PaletteMetrics.brandSquareSize),
            brandView.heightAnchor.constraint(equalToConstant: PaletteMetrics.brandSquareSize),

            queryField.leadingAnchor.constraint(
                equalTo: brandView.trailingAnchor,
                constant: 14
            ),

            escapeKeycap.trailingAnchor.constraint(
                equalTo: searchArea.trailingAnchor,
                constant: -PaletteMetrics.headerInset
            ),
            escapeKeycap.centerYAnchor.constraint(equalTo: searchArea.centerYAnchor),

            queryField.trailingAnchor.constraint(
                equalTo: escapeKeycap.leadingAnchor,
                constant: -16
            ),
            queryField.centerYAnchor.constraint(equalTo: searchArea.centerYAnchor),

            fieldSeparator.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            fieldSeparator.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            fieldSeparator.topAnchor.constraint(equalTo: searchArea.bottomAnchor),
            fieldSeparator.heightAnchor.constraint(equalToConstant: PaletteMetrics.separatorHeight),

            tabsView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            tabsView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            tabsView.topAnchor.constraint(equalTo: fieldSeparator.bottomAnchor),
            tabsView.heightAnchor.constraint(equalToConstant: PaletteMetrics.tabsHeight),

            heroView.leadingAnchor.constraint(
                equalTo: contentView.leadingAnchor,
                constant: PaletteMetrics.listSideInset
            ),
            heroView.trailingAnchor.constraint(
                equalTo: contentView.trailingAnchor,
                constant: -PaletteMetrics.listSideInset
            ),
            heroView.topAnchor.constraint(
                equalTo: tabsView.bottomAnchor,
                constant: PaletteMetrics.listTopInset
            ),
            heroView.heightAnchor.constraint(equalToConstant: PaletteMetrics.heroHeight),

            scrollView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: footerView.topAnchor),

            footerView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            footerView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            footerView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            footerView.heightAnchor.constraint(equalToConstant: PaletteMetrics.footerHeight)
        ])

        // Toggled by the controller: the list sits directly under the
        // (always-visible) tabs row normally, or under the hero card when
        // one is showing.
        let scrollTopToSeparator = scrollView.topAnchor.constraint(equalTo: tabsView.bottomAnchor)
        let scrollTopToHero = scrollView.topAnchor.constraint(
            equalTo: heroView.bottomAnchor,
            constant: PaletteMetrics.listTopInset
        )
        scrollTopToSeparator.isActive = true

        panel.contentView = contentView
        return InstalledConstraints(
            scrollTopToSeparator: scrollTopToSeparator,
            scrollTopToHero: scrollTopToHero
        )
    }

    static func configureFieldEditor(_ editor: NSTextView) {
        editor.font = queryFont
        editor.textColor = .white
        // Block cursor in the result-title tone (white 85%) — violet was
        // right for a hairline, but a filled block of accent overwhelms.
        editor.insertionPointColor = NSColor.white.withAlphaComponent(0.85)
        (editor as? BlockCursorTextView)?.blockCursorWidth = queryFont.pointSize * 0.55
        editor.typingAttributes.merge(queryTextAttributes) { _, newValue in
            newValue
        }
    }

    private static func roundedCornerMask(radius: CGFloat) -> NSImage {
        let edge = radius * 2 + 1
        let image = NSImage(
            size: NSSize(width: edge, height: edge),
            flipped: false
        ) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
            return true
        }
        image.capInsets = NSEdgeInsets(
            top: radius,
            left: radius,
            bottom: radius,
            right: radius
        )
        image.resizingMode = .stretch
        return image
    }

    private static func configurePanel(_ panel: PalettePanel) {
        panel.appearance = NSAppearance(named: .darkAqua)
        panel.level = .statusBar
        panel.collectionBehavior = [
            .canJoinAllSpaces,
            .fullScreenAuxiliary,
            .transient,
            .ignoresCycle
        ]
        panel.isFloatingPanel = true
        panel.isMovableByWindowBackground = true
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
        queryField.font = queryFont
        queryField.textColor = .white
        queryField.allowsEditingTextAttributes = true
        queryField.lineBreakMode = .byTruncatingTail
        // Tagline placeholder renders smaller than the 34pt typed query —
        // it's an invitation, not input; the moment you type, full size.
        // The cell lays the placeholder out against the 34pt line box, so
        // the smaller text needs a baseline drop to sit visually centered,
        // and a head indent so it doesn't touch the insertion point.
        let placeholderStyle = NSMutableParagraphStyle()
        // Clear the block cursor (queryFont.pointSize * 0.55 ≈ 19pt) plus a gap.
        placeholderStyle.firstLineHeadIndent = 26
        queryField.placeholderAttributedString = NSAttributedString(
            string: "Bopop. Everything starts here",
            attributes: [
                .font: NSFont.systemFont(ofSize: 22, weight: .semibold),
                .foregroundColor: NSColor.white.withAlphaComponent(0.35),
                .kern: -0.22,
                .baselineOffset: -7,
                .paragraphStyle: placeholderStyle
            ]
        )
        queryField.translatesAutoresizingMaskIntoConstraints = false
        queryField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        queryField.setAccessibilityLabel("Bopop. Everything starts here")
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
        tableView.intercellSpacing = NSSize(width: 0, height: PaletteMetrics.interRowGap)
        tableView.selectionHighlightStyle = .regular
        tableView.allowsEmptySelection = false
        tableView.allowsMultipleSelection = false
        // Keyboard focus must never leave the query field: if the table
        // becomes first responder (a row click does this by default),
        // Return stops reaching the field editor's doCommandBySelector and
        // silently does nothing.
        tableView.refusesFirstResponder = true
        tableView.backgroundColor = .clear

        scrollView.documentView = tableView
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.scrollerStyle = .overlay
        scrollView.automaticallyAdjustsContentInsets = false
        scrollView.contentInsets = NSEdgeInsets(
            top: PaletteMetrics.listTopInset,
            left: PaletteMetrics.listSideInset,
            bottom: PaletteMetrics.listBottomInset,
            right: PaletteMetrics.listSideInset
        )
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.isHidden = true
    }
}

/// The brand keycap from the app icon, drawn natively: the palette header
/// is already the icon's dark plate, so only the violet keycap renders
/// here — the full plate+keycap icns is for Dock/Finder, where the dark
/// plate has contrast to earn its place.
final class PaletteBrandView: NSView {
    private let gradientLayer = CAGradientLayer()
    private let glyphLabel = NSTextField(labelWithString: "b")
    private let imageLayer = CALayer()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        configureView()
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        gradientLayer.frame = bounds
        imageLayer.frame = bounds
        layer?.cornerRadius = bounds.height * 0.24
        CATransaction.commit()
    }

    /// nil restores the default keycap (gradient + glyph); a non-nil image
    /// swaps in the custom icon, masked by the same continuous-corner
    /// radius the keycap uses (shared via this view's own layer mask).
    func setCustomImage(_ image: NSImage?) {
        imageLayer.contents = image
        imageLayer.isHidden = image == nil
        gradientLayer.isHidden = image != nil
        glyphLabel.isHidden = image != nil
    }

    private func configureView() {
        wantsLayer = true
        translatesAutoresizingMaskIntoConstraints = false
        layer?.cornerCurve = .continuous
        layer?.masksToBounds = true
        setAccessibilityHidden(true)

        // Same ramp and angle as Support/generate-icon.swift's keycap.
        gradientLayer.colors = [
            NSColor.bopopAccentSoft.cgColor,
            NSColor.bopopAccent.cgColor,
            NSColor.bopopAccentDeep.cgColor
        ]
        gradientLayer.locations = [0.0, 0.35, 1.0]
        gradientLayer.startPoint = CGPoint(x: 0.4, y: 0)
        gradientLayer.endPoint = CGPoint(x: 0.6, y: 1)
        layer?.addSublayer(gradientLayer)

        imageLayer.contentsGravity = .resizeAspectFill
        imageLayer.isHidden = true
        layer?.addSublayer(imageLayer)

        glyphLabel.font = .monospacedSystemFont(
            ofSize: PaletteMetrics.brandSquareSize * 0.62,
            weight: .heavy
        )
        glyphLabel.textColor = .white
        glyphLabel.alignment = .center
        glyphLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(glyphLabel)
        NSLayoutConstraint.activate([
            glyphLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            glyphLabel.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }
}

final class PaletteKeycapView: NSView {
    private let label: NSTextField
    private let horizontalPadding: CGFloat
    private let verticalPadding: CGFloat

    init(
        text: String,
        fontSize: CGFloat,
        textAlpha: CGFloat,
        horizontalPadding: CGFloat,
        verticalPadding: CGFloat
    ) {
        label = NSTextField(labelWithString: text)
        self.horizontalPadding = horizontalPadding
        self.verticalPadding = verticalPadding
        super.init(frame: .zero)
        configureView(fontSize: fontSize, textAlpha: textAlpha)
    }

    required init?(coder: NSCoder) {
        nil
    }

    override var intrinsicContentSize: NSSize {
        NSSize(
            width: label.intrinsicContentSize.width + horizontalPadding * 2,
            height: label.intrinsicContentSize.height + verticalPadding * 2
        )
    }

    private func configureView(fontSize: CGFloat, textAlpha: CGFloat) {
        wantsLayer = true
        layer?.cornerRadius = 6
        layer?.cornerCurve = .continuous
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.white.withAlphaComponent(0.15).cgColor
        translatesAutoresizingMaskIntoConstraints = false
        setContentHuggingPriority(.required, for: .horizontal)
        setContentCompressionResistancePriority(.required, for: .horizontal)
        setAccessibilityHidden(true)

        label.font = .monospacedSystemFont(ofSize: fontSize, weight: .medium)
        label.textColor = NSColor.white.withAlphaComponent(textAlpha)
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)

        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(
                equalTo: leadingAnchor,
                constant: horizontalPadding
            ),
            label.trailingAnchor.constraint(
                equalTo: trailingAnchor,
                constant: -horizontalPadding
            ),
            label.topAnchor.constraint(
                equalTo: topAnchor,
                constant: verticalPadding
            ),
            label.bottomAnchor.constraint(
                equalTo: bottomAnchor,
                constant: -verticalPadding
            )
        ])
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
        layer?.borderColor = NSColor.white.withAlphaComponent(0.10).cgColor
    }

    required init?(coder: NSCoder) {
        nil
    }
}

private final class PaletteTintView: NSView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor(
            srgbRed: 22 / 255,
            green: 20 / 255,
            blue: 30 / 255,
            alpha: 0.72
        ).cgColor
    }

    required init?(coder: NSCoder) {
        nil
    }
}

private final class PaletteSeparatorView: NSView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.white.withAlphaComponent(0.07).cgColor
    }

    required init?(coder: NSCoder) {
        nil
    }
}
