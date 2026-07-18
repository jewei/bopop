import AppKit
import BopopKit

final class PaletteRowView: NSTableRowView {
    private static let selectionColor = NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor.white.withAlphaComponent(0.10)
            : NSColor.black.withAlphaComponent(0.06)
    }

    override var isEmphasized: Bool {
        get { true }
        set { super.isEmphasized = true }
    }

    override func drawSelection(in dirtyRect: NSRect) {
        Self.selectionColor.setFill()
        NSBezierPath(
            roundedRect: bounds.insetBy(
                dx: PaletteMetrics.rowSelectionInset,
                dy: 2
            ),
            xRadius: 8,
            yRadius: 8
        ).fill()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }
}

final class ResultRowView: NSTableCellView {
    static let reuseIdentifier = NSUserInterfaceItemIdentifier("ResultRowView")

    private let iconView = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let detailLabel = NSTextField(labelWithString: "")
    private let badgeView = PaletteBadgeView()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        configureView()
    }

    required init?(coder: NSCoder) {
        nil
    }

    func configure(with result: SearchResult) {
        iconView.image = image(for: result.icon)
        titleLabel.stringValue = result.title
        detailLabel.stringValue = result.subtitle ?? ""
        detailLabel.isHidden = result.subtitle == nil
        badgeView.setText(result.badge ?? "")
        badgeView.isHidden = result.badge == nil

        let accessibilityText = [result.title, result.subtitle]
            .compactMap { $0 }
            .joined(separator: " ")
        setAccessibilityLabel(accessibilityText)
    }

    private func configureView() {
        identifier = Self.reuseIdentifier

        iconView.imageScaling = .scaleProportionallyUpOrDown
        iconView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            iconView.widthAnchor.constraint(equalToConstant: 22),
            iconView.heightAnchor.constraint(equalToConstant: 22)
        ])

        titleLabel.font = .systemFont(ofSize: 13, weight: .regular)
        titleLabel.textColor = .labelColor
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.maximumNumberOfLines = 1
        titleLabel.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)

        detailLabel.font = .systemFont(ofSize: 11)
        detailLabel.textColor = .secondaryLabelColor
        detailLabel.alignment = .right
        detailLabel.lineBreakMode = .byTruncatingHead
        detailLabel.maximumNumberOfLines = 1
        detailLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)
        detailLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let rowStack = NSStackView(views: [
            iconView,
            titleLabel,
            detailLabel,
            badgeView
        ])
        rowStack.orientation = .horizontal
        rowStack.alignment = .centerY
        rowStack.spacing = 8
        rowStack.setCustomSpacing(10, after: iconView)
        rowStack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(rowStack)

        NSLayoutConstraint.activate([
            rowStack.leadingAnchor.constraint(
                equalTo: leadingAnchor,
                constant: PaletteMetrics.horizontalInset
            ),
            rowStack.trailingAnchor.constraint(
                equalTo: trailingAnchor,
                constant: -PaletteMetrics.horizontalInset
            ),
            rowStack.centerYAnchor.constraint(equalTo: centerYAnchor),
            detailLabel.widthAnchor.constraint(
                lessThanOrEqualTo: widthAnchor,
                multiplier: 0.45
            )
        ])

        setAccessibilityElement(true)
    }

    private func image(for icon: BopopKit.IconRef) -> NSImage? {
        switch icon {
        case let .appBundle(path), let .file(path):
            return NSWorkspace.shared.icon(forFile: path)
        case let .symbol(name):
            return NSImage(systemSymbolName: name, accessibilityDescription: nil)
        case .none:
            return NSImage(systemSymbolName: "doc", accessibilityDescription: "Item")
        }
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

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateLayerColors()
    }

    private func configureView() {
        wantsLayer = true
        layer?.cornerRadius = 5
        translatesAutoresizingMaskIntoConstraints = false
        setContentHuggingPriority(.required, for: .horizontal)
        setContentCompressionResistancePriority(.required, for: .horizontal)

        label.font = .systemFont(ofSize: 10, weight: .medium)
        label.textColor = .secondaryLabelColor
        label.alignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)

        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 5),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -5),
            label.topAnchor.constraint(equalTo: topAnchor, constant: 2),
            label.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -2)
        ])
        updateLayerColors()
    }

    private func updateLayerColors() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.backgroundColor = NSColor.quaternaryLabelColor.cgColor
        }
    }
}
