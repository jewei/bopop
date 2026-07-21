import AppKit
import BopopKit

/// Raycast-style Actions popover: a non-activating borderless child panel
/// anchored above the footer's right edge, listing every action applicable
/// to the selected result with its shortcut. It never becomes key (borderless
/// panels refuse key by default) — the query field keeps focus and
/// `PaletteController` routes ↑↓/⏎/esc and the shortcut keys here while
/// visible, mirroring the app's route-keys-don't-move-focus pattern.
final class ActionsPanelController {
    var onRun: ((ResultActions.Kind) -> Void)?

    private(set) var isVisible = false
    private var window: NSWindow?
    private var items: [ResultActions.ActionItem] = []
    private var selectedIndex = 0
    private var rowViews: [ActionsPanelRowView] = []

    private static let width: CGFloat = 260
    private static let rowHeight: CGFloat = 36
    private static let headerHeight: CGFloat = 26
    private static let verticalPadding: CGFloat = 6
    private static let sideInset: CGFloat = 6
    /// Gap between the panel's bottom edge and the footer's top separator.
    private static let footerGap: CGFloat = 6

    func show(items: [ResultActions.ActionItem], title: String, over parent: NSWindow) {
        hide()
        guard !items.isEmpty else {
            return
        }
        self.items = items
        selectedIndex = 0
        let window = makeWindow(title: title, over: parent)
        parent.addChildWindow(window, ordered: .above)
        window.orderFront(nil)
        self.window = window
        isVisible = true
    }

    func hide() {
        guard let window else {
            return
        }
        window.parent?.removeChildWindow(window)
        window.orderOut(nil)
        self.window = nil
        rowViews = []
        items = []
        isVisible = false
    }

    func moveSelection(by offset: Int) {
        guard !items.isEmpty else {
            return
        }
        selectedIndex = min(max(selectedIndex + offset, 0), items.count - 1)
        for (index, row) in rowViews.enumerated() {
            row.setSelected(index == selectedIndex)
        }
    }

    func runSelected() {
        guard items.indices.contains(selectedIndex) else {
            return
        }
        onRun?(items[selectedIndex].kind)
    }

    /// Direct-shortcut path (⌘C/⌘⏎/⌘Y/⌘L while open): runs the item of
    /// `kind` if the current result has it; `false` lets the key event fall
    /// through (e.g. ⌘C to the field editor's text copy).
    func run(kind: ResultActions.Kind) -> Bool {
        guard items.contains(where: { $0.kind == kind }) else {
            return false
        }
        onRun?(kind)
        return true
    }

    private func makeWindow(title: String, over parent: NSWindow) -> NSWindow {
        let height = Self.verticalPadding * 2
            + Self.headerHeight
            + CGFloat(items.count) * Self.rowHeight
        let frame = NSRect(
            x: parent.frame.maxX - PaletteMetrics.footerInset - Self.width,
            y: parent.frame.minY + PaletteMetrics.footerHeight + Self.footerGap,
            width: Self.width,
            height: height
        )
        let window = NSPanel(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.level = parent.level
        window.contentView = makeContentView(title: title)
        return window
    }

    private func makeContentView(title: String) -> NSView {
        let container = ActionsPanelBackgroundView()

        let header = NSTextField(labelWithString: title)
        header.font = .monospacedSystemFont(ofSize: 11, weight: .medium)
        header.textColor = NSColor.white.withAlphaComponent(0.45)
        header.lineBreakMode = .byTruncatingTail
        header.maximumNumberOfLines = 1
        header.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(header)

        rowViews = items.enumerated().map { index, item in
            let row = ActionsPanelRowView(item: item)
            row.setSelected(index == selectedIndex)
            row.onClick = { [weak self] in
                self?.onRun?(item.kind)
            }
            return row
        }
        let stack = NSStackView(views: rowViews)
        stack.orientation = .vertical
        stack.spacing = 0
        stack.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(stack)

        NSLayoutConstraint.activate([
            header.topAnchor.constraint(
                equalTo: container.topAnchor,
                constant: Self.verticalPadding
            ),
            header.heightAnchor.constraint(equalToConstant: Self.headerHeight),
            header.leadingAnchor.constraint(
                equalTo: container.leadingAnchor,
                constant: Self.sideInset + 10
            ),
            header.trailingAnchor.constraint(
                lessThanOrEqualTo: container.trailingAnchor,
                constant: -(Self.sideInset + 10)
            ),

            stack.topAnchor.constraint(equalTo: header.bottomAnchor),
            stack.leadingAnchor.constraint(
                equalTo: container.leadingAnchor,
                constant: Self.sideInset
            ),
            stack.trailingAnchor.constraint(
                equalTo: container.trailingAnchor,
                constant: -Self.sideInset
            )
        ])
        for row in rowViews {
            row.heightAnchor.constraint(equalToConstant: Self.rowHeight).isActive = true
        }
        return container
    }
}

/// One action row: title left, keycap shortcut chip right. Keyboard
/// selection uses the accent fill the results table uses; mouse hover uses
/// a quieter white wash so the two states read differently.
private final class ActionsPanelRowView: NSView {
    var onClick: (() -> Void)?

    private let titleLabel: NSTextField
    private let keycap: PaletteKeycapView
    private var selected = false
    private var hovered = false
    private var hoverTrackingArea: NSTrackingArea?

    init(item: ResultActions.ActionItem) {
        titleLabel = NSTextField(labelWithString: item.title)
        keycap = PaletteKeycapView(
            text: item.shortcut,
            fontSize: 11,
            textAlpha: 0.55,
            horizontalPadding: 6,
            verticalPadding: 2
        )
        super.init(frame: .zero)
        configureView()
    }

    required init?(coder: NSCoder) {
        nil
    }

    func setSelected(_ isSelected: Bool) {
        selected = isSelected
        titleLabel.textColor = NSColor.white.withAlphaComponent(isSelected ? 1 : 0.85)
        refreshBackground()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverTrackingArea {
            removeTrackingArea(hoverTrackingArea)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        hoverTrackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        hovered = true
        refreshBackground()
    }

    override func mouseExited(with event: NSEvent) {
        hovered = false
        refreshBackground()
    }

    override func mouseUp(with event: NSEvent) {
        guard bounds.contains(convert(event.locationInWindow, from: nil)) else {
            return
        }
        onClick?()
    }

    /// First click runs the action even when Bopop isn't the active app —
    /// without this the click is consumed as the activation click.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    private func configureView() {
        wantsLayer = true
        layer?.cornerRadius = 8
        layer?.cornerCurve = .continuous
        translatesAutoresizingMaskIntoConstraints = false

        titleLabel.font = .systemFont(ofSize: 13)
        titleLabel.textColor = NSColor.white.withAlphaComponent(0.85)
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.maximumNumberOfLines = 1
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(titleLabel)
        addSubview(keycap)

        NSLayoutConstraint.activate([
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            titleLabel.trailingAnchor.constraint(
                lessThanOrEqualTo: keycap.leadingAnchor,
                constant: -10
            ),
            keycap.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            keycap.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
        refreshBackground()
    }

    private func refreshBackground() {
        let color: CGColor = if selected {
            NSColor.bopopAccent.withAlphaComponent(0.14).cgColor
        } else if hovered {
            NSColor.white.withAlphaComponent(0.06).cgColor
        } else {
            NSColor.clear.cgColor
        }
        layer?.backgroundColor = color
    }
}

/// Near-opaque version of the palette's tint color — the panel floats over
/// arbitrary desktop content, so unlike the palette it doesn't get a
/// behind-window blur to lean on.
private final class ActionsPanelBackgroundView: NSView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor(
            srgbRed: 22 / 255,
            green: 20 / 255,
            blue: 30 / 255,
            alpha: 0.97
        ).cgColor
        layer?.cornerRadius = 12
        layer?.cornerCurve = .continuous
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.white.withAlphaComponent(0.10).cgColor
    }

    required init?(coder: NSCoder) {
        nil
    }
}
