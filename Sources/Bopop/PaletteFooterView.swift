import AppKit

final class PaletteFooterView: NSView {
    private let topSeparator = PaletteFooterSeparatorView()
    private let statusLabel = NSTextField(labelWithString: "Bopop")
    private let navigateLabel = NSTextField(labelWithString: "↑↓ navigate")
    private let copyLabel = NSTextField(labelWithString: "⌘C copy")
    private let primaryLabel = NSTextField(labelWithString: "↵ select")
    private let rightCluster = NSStackView()

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

        rightCluster.setViews(
            [navigateLabel, copyLabel, primaryLabel],
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
