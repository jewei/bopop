import AppKit
import BopopKit

final class ResultRowView: NSTableCellView {
    static let reuseIdentifier = NSUserInterfaceItemIdentifier("ResultRowView")

    private let iconView = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let subtitleLabel = NSTextField(labelWithString: "")
    private let badgeView = NSView()
    private let badgeLabel = NSTextField(labelWithString: "")

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
        subtitleLabel.stringValue = result.subtitle ?? ""
        subtitleLabel.isHidden = result.subtitle == nil
        badgeLabel.stringValue = result.badge ?? ""
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
            iconView.widthAnchor.constraint(equalToConstant: 24),
            iconView.heightAnchor.constraint(equalToConstant: 24)
        ])

        titleLabel.font = .systemFont(ofSize: 15, weight: .semibold)
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        subtitleLabel.font = .systemFont(ofSize: 12)
        subtitleLabel.textColor = .secondaryLabelColor
        subtitleLabel.lineBreakMode = .byTruncatingTail
        subtitleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let textStack = NSStackView(views: [titleLabel, subtitleLabel])
        textStack.orientation = .vertical
        textStack.alignment = .leading
        textStack.spacing = 0

        badgeLabel.font = .systemFont(ofSize: 10, weight: .medium)
        badgeLabel.textColor = .secondaryLabelColor
        badgeLabel.alignment = .center
        badgeLabel.translatesAutoresizingMaskIntoConstraints = false

        badgeView.wantsLayer = true
        badgeView.layer?.backgroundColor = NSColor.quaternaryLabelColor.cgColor
        badgeView.layer?.cornerRadius = 7
        badgeView.translatesAutoresizingMaskIntoConstraints = false
        badgeView.addSubview(badgeLabel)
        NSLayoutConstraint.activate([
            badgeLabel.leadingAnchor.constraint(equalTo: badgeView.leadingAnchor, constant: 6),
            badgeLabel.trailingAnchor.constraint(equalTo: badgeView.trailingAnchor, constant: -6),
            badgeLabel.topAnchor.constraint(equalTo: badgeView.topAnchor, constant: 2),
            badgeLabel.bottomAnchor.constraint(equalTo: badgeView.bottomAnchor, constant: -2)
        ])

        let rowStack = NSStackView(views: [iconView, textStack, badgeView])
        rowStack.orientation = .horizontal
        rowStack.alignment = .centerY
        rowStack.spacing = 10
        rowStack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(rowStack)

        NSLayoutConstraint.activate([
            rowStack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            rowStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            rowStack.centerYAnchor.constraint(equalTo: centerYAnchor),
            rowStack.topAnchor.constraint(greaterThanOrEqualTo: topAnchor, constant: 4),
            rowStack.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor, constant: -4)
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
