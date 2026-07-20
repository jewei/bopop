import AppKit

final class PaletteFooterView: NSView {
    private let topSeparator = PaletteFooterSeparatorView()
    private let statusLabel = NSTextField(labelWithString: "Bopop")
    private let navigateLabel = NSTextField(labelWithString: "↑↓ navigate")
    private let copyLabel = NSTextField(labelWithString: "⌘C copy")
    private let primaryLabel = NSTextField(labelWithString: "↵ select")
    private let gearButton = PaletteFooterGearButton()
    private let rightCluster = NSStackView()

    /// Wired by `PaletteController`, which forwards to `AppDelegate` —
    /// follows the same closure-callback style as `onWillShow`.
    var onShowSettings: (() -> Void)?
    var onOpenScriptsFolder: (() -> Void)?
    var onQuit: (() -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        configureView()
    }

    required init?(coder: NSCoder) {
        nil
    }

    func setStatus(_ text: String) {
        statusLabel.stringValue = text
        statusLabel.toolTip = text
    }

    func setActions(primary: String?, hasCopy: Bool) {
        let verb = primary?.lowercased() ?? "select"
        primaryLabel.stringValue = "↵ \(verb)"
        primaryLabel.setAccessibilityLabel("Return activates the selected result")
        copyLabel.isHidden = !hasCopy
    }

    private func configureView() {
        translatesAutoresizingMaskIntoConstraints = false

        topSeparator.translatesAutoresizingMaskIntoConstraints = false
        addSubview(topSeparator)

        configureLabel(statusLabel)
        statusLabel.lineBreakMode = .byTruncatingTail
        statusLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(statusLabel)

        configureLabel(navigateLabel)
        navigateLabel.setAccessibilityLabel("Up and down arrows navigate results")

        configureLabel(copyLabel)
        copyLabel.isHidden = true
        copyLabel.setAccessibilityLabel("Command C copies the selected result")

        configureLabel(primaryLabel)
        primaryLabel.setAccessibilityLabel("Return selects the selected result")

        gearButton.target = self
        gearButton.action = #selector(gearButtonTapped(_:))
        gearButton.setAccessibilityLabel("More options")

        // All four views share the .leading gravity area, so setViews'
        // ordering (not per-item gravity) determines layout — the whole
        // rightCluster stack is separately pinned to the footer's trailing
        // edge below. Mixing gravity areas here isn't needed (HANDOVER
        // gotcha #6 applies when views must be pinned independently within
        // a stack; this cluster is pinned as a single unit instead).
        rightCluster.setViews(
            [navigateLabel, copyLabel, primaryLabel, gearButton],
            in: .leading
        )
        rightCluster.orientation = .horizontal
        rightCluster.alignment = .centerY
        rightCluster.spacing = 14
        rightCluster.translatesAutoresizingMaskIntoConstraints = false
        rightCluster.setContentHuggingPriority(.required, for: .horizontal)
        rightCluster.setContentCompressionResistancePriority(.required, for: .horizontal)
        addSubview(rightCluster)

        NSLayoutConstraint.activate([
            topSeparator.leadingAnchor.constraint(equalTo: leadingAnchor),
            topSeparator.trailingAnchor.constraint(equalTo: trailingAnchor),
            topSeparator.topAnchor.constraint(equalTo: topAnchor),
            topSeparator.heightAnchor.constraint(equalToConstant: PaletteMetrics.separatorHeight),

            statusLabel.leadingAnchor.constraint(
                equalTo: leadingAnchor,
                constant: PaletteMetrics.footerInset
            ),
            statusLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            statusLabel.trailingAnchor.constraint(
                lessThanOrEqualTo: rightCluster.leadingAnchor,
                constant: -14
            ),

            rightCluster.trailingAnchor.constraint(
                equalTo: trailingAnchor,
                constant: -PaletteMetrics.footerInset
            ),
            rightCluster.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }

    private func configureLabel(_ label: NSTextField) {
        label.font = .monospacedSystemFont(ofSize: 11, weight: .medium)
        label.textColor = NSColor.white.withAlphaComponent(0.45)
        label.maximumNumberOfLines = 1
    }

    @objc private func gearButtonTapped(_ sender: NSButton) {
        let menu = NSMenu()

        let settingsItem = NSMenuItem(
            title: "Settings…",
            action: #selector(settingsMenuItemTapped),
            keyEquivalent: ""
        )
        settingsItem.target = self
        menu.addItem(settingsItem)

        let scriptsItem = NSMenuItem(
            title: "Open Scripts Folder",
            action: #selector(scriptsMenuItemTapped),
            keyEquivalent: ""
        )
        scriptsItem.target = self
        menu.addItem(scriptsItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(
            title: "Quit Bopop",
            action: #selector(quitMenuItemTapped),
            keyEquivalent: ""
        )
        quitItem.target = self
        menu.addItem(quitItem)

        menu.popUp(
            positioning: nil,
            at: NSPoint(x: 0, y: sender.bounds.maxY + 6),
            in: sender
        )
    }

    @objc private func settingsMenuItemTapped() {
        onShowSettings?()
    }

    @objc private func scriptsMenuItemTapped() {
        onOpenScriptsFolder?()
    }

    @objc private func quitMenuItemTapped() {
        onQuit?()
    }
}

/// Borderless gearshape icon button with a hover-brighten state
/// (white 0.45 idle → 0.8 hovered), matching the footer label hierarchy.
private final class PaletteFooterGearButton: NSButton {
    private static let idleAlpha: CGFloat = 0.45
    private static let hoverAlpha: CGFloat = 0.8

    private var hoverTrackingArea: NSTrackingArea?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        configureButton()
    }

    required init?(coder: NSCoder) {
        nil
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
        contentTintColor = NSColor.white.withAlphaComponent(Self.hoverAlpha)
    }

    override func mouseExited(with event: NSEvent) {
        contentTintColor = NSColor.white.withAlphaComponent(Self.idleAlpha)
    }

    private func configureButton() {
        translatesAutoresizingMaskIntoConstraints = false
        isBordered = false
        bezelStyle = .regularSquare
        imagePosition = .imageOnly
        setButtonType(.momentaryChange)
        setContentHuggingPriority(.required, for: .horizontal)
        setContentCompressionResistancePriority(.required, for: .horizontal)
        let config = NSImage.SymbolConfiguration(pointSize: 13, weight: .medium)
        image = NSImage(
            systemSymbolName: "gearshape",
            accessibilityDescription: "More options"
        )?.withSymbolConfiguration(config)
        contentTintColor = NSColor.white.withAlphaComponent(Self.idleAlpha)
    }
}

private final class PaletteFooterSeparatorView: NSView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.white.withAlphaComponent(0.07).cgColor
    }

    required init?(coder: NSCoder) {
        nil
    }
}
