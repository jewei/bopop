import AppKit

final class PaletteFooterView: NSView {
    private let topSeparator = PaletteFooterSeparatorView()
    private let statusLabel = NSTextField(labelWithString: "")
    private let primaryLabel = NSTextField(labelWithString: "")
    private let copyLabel = NSTextField(labelWithString: "Copy")
    private let returnKeycap = PaletteKeycapView(text: "↩")
    private let copyKeycap = PaletteKeycapView(text: "⌘C")
    private let actionDivider = PaletteFooterSeparatorView()
    private let rightCluster = NSStackView()
    private let copyCluster = NSStackView()
    private var statusTrailingWithActions: NSLayoutConstraint!
    private var statusTrailingWithoutActions: NSLayoutConstraint!

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
        guard let primary else {
            rightCluster.isHidden = true
            statusTrailingWithActions.isActive = false
            statusTrailingWithoutActions.isActive = true
            return
        }

        primaryLabel.stringValue = primary
        primaryLabel.setAccessibilityLabel("Return runs \(primary)")
        copyCluster.isHidden = !hasCopy
        statusTrailingWithoutActions.isActive = false
        statusTrailingWithActions.isActive = true
        rightCluster.isHidden = false
    }

    private func configureView() {
        translatesAutoresizingMaskIntoConstraints = false

        topSeparator.translatesAutoresizingMaskIntoConstraints = false
        addSubview(topSeparator)

        let statusIcon = NSImageView()
        statusIcon.image = NSImage(
            systemSymbolName: "command.square.fill",
            accessibilityDescription: nil
        )?.withSymbolConfiguration(
            NSImage.SymbolConfiguration(pointSize: 13, weight: .regular)
        )
        statusIcon.contentTintColor = .bopopAccent
        statusIcon.imageScaling = .scaleProportionallyDown
        statusIcon.translatesAutoresizingMaskIntoConstraints = false
        statusIcon.setAccessibilityHidden(true)

        configureLabel(statusLabel)
        statusLabel.lineBreakMode = .byTruncatingTail
        statusLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let leftCluster = NSStackView(views: [statusIcon, statusLabel])
        leftCluster.orientation = .horizontal
        leftCluster.alignment = .centerY
        leftCluster.spacing = 6
        leftCluster.translatesAutoresizingMaskIntoConstraints = false
        addSubview(leftCluster)

        configureLabel(primaryLabel)
        primaryLabel.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)

        configureLabel(copyLabel)
        copyLabel.setAccessibilityLabel("Command C copies the selected result")

        actionDivider.translatesAutoresizingMaskIntoConstraints = false
        copyCluster.setViews(
            [actionDivider, copyLabel, copyKeycap],
            in: .leading
        )
        copyCluster.orientation = .horizontal
        copyCluster.alignment = .centerY
        copyCluster.spacing = 6

        rightCluster.setViews(
            [primaryLabel, returnKeycap, copyCluster],
            in: .leading
        )
        rightCluster.orientation = .horizontal
        rightCluster.alignment = .centerY
        rightCluster.spacing = 6
        rightCluster.translatesAutoresizingMaskIntoConstraints = false
        rightCluster.isHidden = true
        addSubview(rightCluster)

        statusTrailingWithActions = leftCluster.trailingAnchor.constraint(
            lessThanOrEqualTo: rightCluster.leadingAnchor,
            constant: -12
        )
        statusTrailingWithoutActions = leftCluster.trailingAnchor.constraint(
            lessThanOrEqualTo: trailingAnchor,
            constant: -PaletteMetrics.horizontalInset
        )

        NSLayoutConstraint.activate([
            topSeparator.leadingAnchor.constraint(equalTo: leadingAnchor),
            topSeparator.trailingAnchor.constraint(equalTo: trailingAnchor),
            topSeparator.topAnchor.constraint(equalTo: topAnchor),
            topSeparator.heightAnchor.constraint(equalToConstant: PaletteMetrics.separatorHeight),

            statusIcon.widthAnchor.constraint(equalToConstant: 13),
            statusIcon.heightAnchor.constraint(equalToConstant: 13),

            leftCluster.leadingAnchor.constraint(
                equalTo: leadingAnchor,
                constant: PaletteMetrics.horizontalInset
            ),
            leftCluster.centerYAnchor.constraint(equalTo: centerYAnchor),
            statusTrailingWithoutActions,

            actionDivider.widthAnchor.constraint(equalToConstant: PaletteMetrics.separatorHeight),
            actionDivider.heightAnchor.constraint(equalToConstant: 12),

            rightCluster.trailingAnchor.constraint(
                equalTo: trailingAnchor,
                constant: -PaletteMetrics.horizontalInset
            ),
            rightCluster.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }

    private func configureLabel(_ label: NSTextField) {
        label.font = .systemFont(ofSize: 11)
        label.textColor = .secondaryLabelColor
        label.maximumNumberOfLines = 1
    }
}

private final class PaletteKeycapView: NSView {
    private let label: NSTextField

    init(text: String) {
        label = NSTextField(labelWithString: text)
        super.init(frame: .zero)
        configureView()
    }

    required init?(coder: NSCoder) {
        nil
    }

    override var intrinsicContentSize: NSSize {
        NSSize(
            width: label.intrinsicContentSize.width + 10,
            height: 18
        )
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateLayerColors()
    }

    private func configureView() {
        wantsLayer = true
        layer?.cornerRadius = 4
        translatesAutoresizingMaskIntoConstraints = false
        setContentHuggingPriority(.required, for: .horizontal)
        setContentCompressionResistancePriority(.required, for: .horizontal)
        setAccessibilityHidden(true)

        label.font = .systemFont(ofSize: 11, weight: .medium)
        label.textColor = .secondaryLabelColor
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)

        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 18),
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 5),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -5),
            label.topAnchor.constraint(equalTo: topAnchor, constant: 1),
            label.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -1)
        ])
        updateLayerColors()
    }

    private func updateLayerColors() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.backgroundColor = NSColor.quaternaryLabelColor.cgColor
        }
    }
}

private final class PaletteFooterSeparatorView: NSView {
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
