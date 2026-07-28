import AppKit
import BopopKit
import QuartzCore

final class PaletteRowView: NSTableRowView {
    override var isSelected: Bool {
        didSet {
            updateCellSelection()
        }
    }

    override var isEmphasized: Bool {
        get { true }
        set { super.isEmphasized = true }
    }

    override func didAddSubview(_ subview: NSView) {
        super.didAddSubview(subview)
        updateCellSelection()
    }

    override func drawSelection(in dirtyRect: NSRect) {
        let capsuleRect = bounds.insetBy(dx: 0, dy: 2)
        let capsulePath = NSBezierPath(
            roundedRect: capsuleRect,
            xRadius: PaletteMetrics.selectionRadius,
            yRadius: PaletteMetrics.selectionRadius
        )
        NSColor.bopopAccent.withAlphaComponent(0.14).setFill()
        capsulePath.fill()

        let strokeRect = capsuleRect.insetBy(dx: 0.5, dy: 0.5)
        let strokePath = NSBezierPath(
            roundedRect: strokeRect,
            xRadius: PaletteMetrics.selectionRadius - 0.5,
            yRadius: PaletteMetrics.selectionRadius - 0.5
        )
        strokePath.lineWidth = 1
        NSColor.bopopAccent.withAlphaComponent(0.30).setStroke()
        strokePath.stroke()
    }

    private func updateCellSelection() {
        // AppKit sets isSelected during row initialization, before any cell
        // view exists — viewAtColumn: throws on the empty row then.
        guard numberOfColumns > 0 else {
            return
        }
        (view(atColumn: 0) as? ResultRowView)?.setSelected(isSelected)
    }
}

final class ResultRowView: NSTableCellView {
    static let reuseIdentifier = NSUserInterfaceItemIdentifier("ResultRowView")

    private let iconView = ResultIconView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let detailLabel = NSTextField(labelWithString: "")
    private let badgeView = PaletteBadgeView()
    private let returnKeycap = PaletteKeycapView(
        text: "↵",
        fontSize: 10,
        textAlpha: 0.50,
        horizontalPadding: 7,
        verticalPadding: 3
    )
    private var selected = false

    /// Right-click selects this row and opens the ⌘K actions panel — the
    /// panel is already independent of how it was summoned, so this is just
    /// the mouse-first route to the same list. Re-assigned on every
    /// `configure` because rows are reused across results.
    var onRightClick: (() -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        configureView()
    }

    required init?(coder: NSCoder) {
        nil
    }

    func configure(with result: SearchResult) {
        iconView.configure(with: result.icon)
        titleLabel.stringValue = result.title
        detailLabel.stringValue = result.subtitle ?? ""
        detailLabel.isHidden = result.subtitle == nil
        badgeView.setText(result.badge ?? "")
        badgeView.isHidden = result.badge == nil
        applySelectionStyle()

        let accessibilityText = [result.title, result.subtitle]
            .compactMap { $0 }
            .joined(separator: " ")
        setAccessibilityLabel(accessibilityText)
    }

    func setSelected(_ isSelected: Bool) {
        selected = isSelected
        applySelectionStyle()
    }

    override func rightMouseDown(with event: NSEvent) {
        onRightClick?()
    }

    /// First right-click works even when Bopop isn't the active app, matching
    /// how the actions panel's own rows accept a first mouse.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    private func configureView() {
        identifier = Self.reuseIdentifier

        iconView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            iconView.widthAnchor.constraint(equalToConstant: PaletteMetrics.iconSize),
            iconView.heightAnchor.constraint(equalToConstant: PaletteMetrics.iconSize)
        ])

        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.maximumNumberOfLines = 1
        titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        detailLabel.alignment = .left
        detailLabel.lineBreakMode = .byTruncatingHead
        detailLabel.maximumNumberOfLines = 1
        detailLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let textStack = NSStackView(views: [titleLabel, detailLabel])
        textStack.orientation = .vertical
        textStack.alignment = .leading
        textStack.spacing = 2
        // The text block must be the ONLY stretchable member, or Auto Layout
        // breaks the tie arbitrarily per reuse pass and the ↵ keycap wanders.
        textStack.setContentHuggingPriority(NSLayoutConstraint.Priority(1), for: .horizontal)
        textStack.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        badgeView.setContentHuggingPriority(.required, for: .horizontal)
        badgeView.setContentCompressionResistancePriority(.required, for: .horizontal)
        returnKeycap.setContentHuggingPriority(.required, for: .horizontal)
        returnKeycap.setContentCompressionResistancePriority(.required, for: .horizontal)

        returnKeycap.isHidden = true

        // Gravity areas, not a flat view list: leading cluster hugs left,
        // trailing cluster (badge + ↵) pins right, free space in between.
        let rowStack = NSStackView()
        rowStack.addView(iconView, in: .leading)
        rowStack.addView(textStack, in: .leading)
        rowStack.addView(badgeView, in: .trailing)
        rowStack.addView(returnKeycap, in: .trailing)
        rowStack.orientation = .horizontal
        rowStack.alignment = .centerY
        rowStack.spacing = 8
        rowStack.setCustomSpacing(12, after: iconView)
        rowStack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(rowStack)

        NSLayoutConstraint.activate([
            rowStack.leadingAnchor.constraint(
                equalTo: leadingAnchor,
                constant: PaletteMetrics.rowContentPadding
            ),
            rowStack.trailingAnchor.constraint(
                equalTo: trailingAnchor,
                constant: -PaletteMetrics.rowContentPadding
            ),
            rowStack.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])

        applySelectionStyle()
        setAccessibilityElement(true)
    }

    private func applySelectionStyle() {
        titleLabel.font = .systemFont(
            ofSize: selected ? 14.5 : 14,
            weight: selected ? .semibold : .medium
        )
        titleLabel.textColor = NSColor.white.withAlphaComponent(selected ? 1 : 0.85)
        detailLabel.font = .systemFont(ofSize: selected ? 11.5 : 11, weight: .regular)
        detailLabel.textColor = NSColor.white.withAlphaComponent(0.45)
        iconView.setSelected(selected)
        returnKeycap.isHidden = !selected
    }
}

private final class ResultIconView: NSView {
    private let tileView = NSView()
    private let gradientLayer = CAGradientLayer()
    private let imageView = NSImageView()
    private var showsTile = false
    private var selected = false

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
        gradientLayer.frame = tileView.bounds
        CATransaction.commit()
    }

    // Shared across every row/reuse pass: NSWorkspace.shared.icon(forFile:)
    // does real disk I/O (icon resource lookup) and was measured to run
    // once per visible row per keystroke, since the table reloads/redraws
    // rows on every ranked-results update. Keyed by path since a path is
    // stable identity for what NSWorkspace hands back for that file.
    ///
    /// Bounded by real decoded cost, not entry count: file search walks an
    /// unbounded set of paths, so an unbounded cache grew for as long as the
    /// user kept browsing. Icons are also downsampled to the size actually
    /// drawn — `NSWorkspace` hands back a multi-representation image far
    /// larger than one 32pt row needs.
    private static let iconCache: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        cache.totalCostLimit = 16 * 1024 * 1024
        return cache
    }()

    /// Invalidates an in-flight async icon load when the row is reused for a
    /// different result, so a slow decode can't paint the wrong icon into a
    /// row that has since scrolled away.
    private var iconLoadToken = UUID()

    func configure(with icon: BopopKit.IconRef) {
        let token = UUID()
        iconLoadToken = token
        switch icon {
        case let .appBundle(path), let .file(path):
            showsTile = false
            imageView.contentTintColor = nil
            imageView.imageScaling = .scaleProportionallyUpOrDown
            if let cached = Self.cachedIcon(forFile: path) {
                imageView.image = cached
            } else {
                // Cold icons hit the disk inside `NSWorkspace.icon(forFile:)`.
                // That used to run inline in cell configuration — i.e. on the
                // render path, for every newly-visible row. Show the generic
                // placeholder and swap in the real icon when it arrives.
                imageView.image = Self.placeholderIcon
                Task { [weak self] in
                    let image = await Self.loadIcon(forFile: path)
                    guard let self, iconLoadToken == token else {
                        return
                    }
                    imageView.image = image
                }
            }
        case let .symbol(name):
            configureSymbol(named: name)
        case .none:
            configureSymbol(named: "doc")
        }
        updateTileStyle()
    }

    func setSelected(_ isSelected: Bool) {
        selected = isSelected
        updateTileStyle()
    }

    private static let placeholderIcon = NSWorkspace.shared.icon(
        for: .data
    )

    private static func cachedIcon(forFile path: String) -> NSImage? {
        iconCache.object(forKey: path as NSString)
    }

    /// The `NSWorkspace` lookup is the part that touches the disk, so it runs
    /// off the main actor; the downsample and the cache write come back here
    /// because `NSImage` drawing is main-actor work.
    private static func loadIcon(forFile path: String) async -> NSImage {
        if let cached = cachedIcon(forFile: path) {
            return cached
        }
        let source = await Task.detached(priority: .userInitiated) {
            NSWorkspace.shared.icon(forFile: path)
        }.value
        let (icon, cost) = downsampled(source)
        iconCache.setObject(icon, forKey: path as NSString, cost: cost)
        return icon
    }

    /// Redraws at the size rows actually use, and reports the resulting
    /// bitmap's byte cost so `totalCostLimit` bounds real memory rather than
    /// a count of images whose sizes vary wildly.
    private static func downsampled(_ source: NSImage) -> (NSImage, Int) {
        let side = PaletteMetrics.iconSize * 2
        let size = NSSize(width: side, height: side)
        let image = NSImage(size: size, flipped: false) { rect in
            source.draw(in: rect)
            return true
        }
        return (image, Int(side * side * 4))
    }

    private func configureView() {
        wantsLayer = true

        tileView.wantsLayer = true
        tileView.layer?.cornerRadius = PaletteMetrics.tileRadius
        tileView.layer?.cornerCurve = .continuous
        tileView.layer?.masksToBounds = true
        tileView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(tileView)

        gradientLayer.colors = [
            NSColor.bopopAccent.cgColor,
            NSColor.bopopAccentDeep.cgColor
        ]
        gradientLayer.startPoint = CGPoint(x: 0, y: 0)
        gradientLayer.endPoint = CGPoint(x: 1, y: 1)
        tileView.layer?.addSublayer(gradientLayer)

        imageView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(imageView)

        NSLayoutConstraint.activate([
            tileView.leadingAnchor.constraint(equalTo: leadingAnchor),
            tileView.trailingAnchor.constraint(equalTo: trailingAnchor),
            tileView.topAnchor.constraint(equalTo: topAnchor),
            tileView.bottomAnchor.constraint(equalTo: bottomAnchor),

            imageView.leadingAnchor.constraint(equalTo: leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: trailingAnchor),
            imageView.topAnchor.constraint(equalTo: topAnchor),
            imageView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    private func configureSymbol(named name: String) {
        showsTile = true
        imageView.image = NSImage(
            systemSymbolName: name,
            accessibilityDescription: nil
        )?.withSymbolConfiguration(
            NSImage.SymbolConfiguration(pointSize: 14, weight: .medium)
        )
        imageView.contentTintColor = .white
        imageView.imageScaling = .scaleProportionallyDown
    }

    private func updateTileStyle() {
        tileView.isHidden = !showsTile
        tileView.layer?.backgroundColor = NSColor.white
            .withAlphaComponent(0.06)
            .cgColor

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        gradientLayer.isHidden = !showsTile || !selected
        CATransaction.commit()
    }
}

private final class PaletteBadgeView: NSView {
    private let label = NSTextField(labelWithString: "")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        configureView()
    }

    required init?(coder: NSCoder) {
        nil
    }

    func setText(_ text: String) {
        label.stringValue = text
    }

    private func configureView() {
        wantsLayer = true
        layer?.cornerRadius = 5
        layer?.cornerCurve = .continuous
        layer?.backgroundColor = NSColor.white.withAlphaComponent(0.08).cgColor
        translatesAutoresizingMaskIntoConstraints = false
        setContentHuggingPriority(.required, for: .horizontal)
        setContentCompressionResistancePriority(.required, for: .horizontal)

        label.font = .monospacedSystemFont(ofSize: 10, weight: .medium)
        label.textColor = NSColor.white.withAlphaComponent(0.55)
        label.alignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)

        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 5),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -5),
            label.topAnchor.constraint(equalTo: topAnchor, constant: 2),
            label.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -2)
        ])
    }
}
