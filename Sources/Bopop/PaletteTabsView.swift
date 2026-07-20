import AppKit
import BopopKit

/// Pill tab row unified with modes — always visible directly under the
/// field hairline. Reflects the EFFECTIVE mode (which may be a
/// prefix-typed mode, not just `stickyMode`); `PaletteController` is
/// responsible for calling `setActive` at every point the effective mode
/// changes. A pill click enters that mode the same way a command row does.
final class PaletteTabsView: NSView {
    static let orderedTabs: [(Mode, String)] = [
        (.general, "All"),
        (.apps, "Apps"),
        (.fileSearch, "Files"),
        (.clipboard, "Clipboard"),
        (.emoji, "Emoji"),
        (.translation, "Translate")
    ]

    /// Wired by `PaletteController` — a pill click enters that mode,
    /// mirroring `actionRunner.onModeChange` for command rows.
    var onSelect: ((Mode) -> Void)?

    private let stackView = NSStackView()
    private var pills: [Mode: PaletteTabPillButton] = [:]
    private var activeMode: Mode = .general

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        configureView()
    }

    required init?(coder: NSCoder) {
        nil
    }

    func setActive(_ mode: Mode) {
        guard activeMode != mode else {
            return
        }
        activeMode = mode
        for (pillMode, pill) in pills {
            pill.setActive(pillMode == mode)
        }
    }

    private func configureView() {
        translatesAutoresizingMaskIntoConstraints = false

        stackView.orientation = .horizontal
        stackView.alignment = .centerY
        stackView.spacing = 6
        stackView.translatesAutoresizingMaskIntoConstraints = false

        var views: [NSView] = []
        for (mode, title) in Self.orderedTabs {
            let pill = PaletteTabPillButton(title: title, mode: mode)
            pill.target = self
            pill.action = #selector(pillTapped(_:))
            pill.setActive(mode == activeMode)
            pills[mode] = pill
            views.append(pill)
        }
        stackView.setViews(views, in: .leading)
        addSubview(stackView)

        NSLayoutConstraint.activate([
            stackView.leadingAnchor.constraint(
                equalTo: leadingAnchor,
                constant: PaletteMetrics.footerInset
            ),
            stackView.topAnchor.constraint(equalTo: topAnchor),
            stackView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    @objc private func pillTapped(_ sender: PaletteTabPillButton) {
        onSelect?(sender.mode)
    }
}

/// Capsule pill button for a single tab. Hover-brighten mirrors
/// `PaletteFooterGearButton` (idle → hover text alpha); adds an active
/// fill/text state on top of that for the currently effective mode.
private final class PaletteTabPillButton: NSButton {
    private static let inactiveTextAlpha: CGFloat = 0.45
    private static let hoverTextAlpha: CGFloat = 0.7
    private static let activeTextAlpha: CGFloat = 0.92
    private static let activeFillAlpha: CGFloat = 0.25
    private static let horizontalPadding: CGFloat = 14

    let mode: Mode
    private var isActive = false
    private var hoverTrackingArea: NSTrackingArea?
    private let label: NSTextField

    init(title: String, mode: Mode) {
        self.mode = mode
        label = NSTextField(labelWithString: title)
        super.init(frame: .zero)
        configureButton()
    }

    required init?(coder: NSCoder) {
        nil
    }

    override var intrinsicContentSize: NSSize {
        NSSize(
            width: label.intrinsicContentSize.width + Self.horizontalPadding * 2,
            height: PaletteMetrics.tabsHeight
        )
    }

    func setActive(_ active: Bool) {
        isActive = active
        updateAppearance()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverTrackingArea {
            removeTrackingArea(hoverTrackingArea)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeInKeyWindow],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        hoverTrackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        guard !isActive else {
            return
        }
        label.textColor = NSColor.white.withAlphaComponent(Self.hoverTextAlpha)
    }

    override func mouseExited(with event: NSEvent) {
        guard !isActive else {
            return
        }
        label.textColor = NSColor.white.withAlphaComponent(Self.inactiveTextAlpha)
    }

    override func layout() {
        super.layout()
        layer?.cornerRadius = bounds.height / 2
    }

    private func configureButton() {
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.cornerCurve = .continuous
        isBordered = false
        bezelStyle = .regularSquare
        setButtonType(.momentaryChange)
        title = ""
        setContentHuggingPriority(.required, for: .horizontal)
        setContentCompressionResistancePriority(.required, for: .horizontal)
        setAccessibilityLabel(label.stringValue)

        heightAnchor.constraint(equalToConstant: PaletteMetrics.tabsHeight).isActive = true

        label.font = .monospacedSystemFont(ofSize: 11, weight: .medium)
        label.alignment = .center
        label.isEditable = false
        label.isSelectable = false
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)

        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(
                equalTo: leadingAnchor,
                constant: Self.horizontalPadding
            ),
            label.trailingAnchor.constraint(
                equalTo: trailingAnchor,
                constant: -Self.horizontalPadding
            ),
            label.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])

        updateAppearance()
    }

    private func updateAppearance() {
        layer?.backgroundColor = isActive
            ? NSColor.bopopAccent.withAlphaComponent(Self.activeFillAlpha).cgColor
            : NSColor.clear.cgColor
        label.textColor = NSColor.white.withAlphaComponent(
            isActive ? Self.activeTextAlpha : Self.inactiveTextAlpha
        )
    }
}
