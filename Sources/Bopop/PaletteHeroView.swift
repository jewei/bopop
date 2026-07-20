import AppKit
import BopopKit

/// Renders `HeroContent` as a "before → after" card: a source pane, an arrow
/// with an optional note, and a target pane — mirrored left/right. Sits
/// between the query field and the results list whenever the top-ranked
/// result carries hero content (see `HeroPresentation.split`).
final class PaletteHeroView: NSView {
    private static let horizontalInset: CGFloat = 20
    private static let paneGap: CGFloat = 16
    private static let noteMaxWidth: CGFloat = 140

    private let leftValueLabel = NSTextField(labelWithString: "")
    private let rightValueLabel = NSTextField(labelWithString: "")
    private let leftBadge = PaletteHeroBadgeView()
    private let rightBadge = PaletteHeroBadgeView()
    private let arrowLabel = NSTextField(labelWithString: "→")
    private let noteLabel = NSTextField(labelWithString: "")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        configureView()
    }

    required init?(coder: NSCoder) {
        nil
    }

    func configure(with hero: HeroContent) {
        leftValueLabel.stringValue = hero.left
        rightValueLabel.stringValue = hero.right
        leftBadge.setText(hero.leftBadge ?? "")
        leftBadge.isHidden = hero.leftBadge == nil
        rightBadge.setText(hero.rightBadge ?? "")
        rightBadge.isHidden = hero.rightBadge == nil
        noteLabel.stringValue = hero.note ?? ""
        noteLabel.isHidden = hero.note == nil

        let accessibilityText = [hero.left, hero.leftBadge, hero.right, hero.rightBadge, hero.note]
            .compactMap { $0 }
            .joined(separator: ", ")
        setAccessibilityLabel(accessibilityText)
    }

    private func configureView() {
        wantsLayer = true
        // This lives INSIDE the already-masked panel content view, so a plain
        // layer corner radius is fine here — the maskImage gotcha only
        // applies to the panel's own NSVisualEffectView (HANDOVER gotcha #5).
        layer?.backgroundColor = NSColor.white.withAlphaComponent(0.04).cgColor
        layer?.cornerRadius = 10
        layer?.cornerCurve = .continuous
        translatesAutoresizingMaskIntoConstraints = false
        setAccessibilityElement(true)
        setAccessibilityRole(.group)

        configureValueLabel(leftValueLabel, alignment: .left)
        configureValueLabel(rightValueLabel, alignment: .right)

        arrowLabel.font = .systemFont(ofSize: 20, weight: .regular)
        arrowLabel.textColor = NSColor.white.withAlphaComponent(0.55)
        arrowLabel.alignment = .center
        arrowLabel.setAccessibilityHidden(true)

        noteLabel.font = .systemFont(ofSize: 10, weight: .regular)
        noteLabel.textColor = NSColor.white.withAlphaComponent(0.35)
        noteLabel.alignment = .center
        noteLabel.lineBreakMode = .byTruncatingTail
        noteLabel.maximumNumberOfLines = 1
        noteLabel.isHidden = true
        noteLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        noteLabel.widthAnchor.constraint(
            lessThanOrEqualToConstant: Self.noteMaxWidth
        ).isActive = true

        let leftStack = NSStackView(views: [leftValueLabel, leftBadge])
        leftStack.orientation = .vertical
        leftStack.alignment = .leading
        leftStack.spacing = 6
        leftStack.translatesAutoresizingMaskIntoConstraints = false

        let rightStack = NSStackView(views: [rightValueLabel, rightBadge])
        rightStack.orientation = .vertical
        rightStack.alignment = .trailing
        rightStack.spacing = 6
        rightStack.translatesAutoresizingMaskIntoConstraints = false

        let centerStack = NSStackView(views: [arrowLabel, noteLabel])
        centerStack.orientation = .vertical
        centerStack.alignment = .centerX
        centerStack.spacing = 4
        centerStack.translatesAutoresizingMaskIntoConstraints = false
        centerStack.setContentHuggingPriority(.required, for: .horizontal)
        centerStack.setContentCompressionResistancePriority(.required, for: .horizontal)

        for subview in [leftStack, rightStack, centerStack] {
            addSubview(subview)
        }

        // No dividers, no reserved center column: the arrow hugs its content
        // at the card's center and each pane flexes to fill everything on its
        // side, so long values (timezone descriptions) get maximum width.
        // Badges cap at their pane's width so they truncate, never overflow.
        leftBadge.widthAnchor.constraint(
            lessThanOrEqualTo: leftStack.widthAnchor
        ).isActive = true
        rightBadge.widthAnchor.constraint(
            lessThanOrEqualTo: rightStack.widthAnchor
        ).isActive = true

        NSLayoutConstraint.activate([
            leftStack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Self.horizontalInset),
            leftStack.trailingAnchor.constraint(equalTo: centerStack.leadingAnchor, constant: -Self.paneGap),
            leftStack.centerYAnchor.constraint(equalTo: centerYAnchor),

            centerStack.centerXAnchor.constraint(equalTo: centerXAnchor),
            centerStack.centerYAnchor.constraint(equalTo: centerYAnchor),

            rightStack.leadingAnchor.constraint(equalTo: centerStack.trailingAnchor, constant: Self.paneGap),
            rightStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Self.horizontalInset),
            rightStack.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }

    private func configureValueLabel(_ label: NSTextField, alignment: NSTextAlignment) {
        label.font = .monospacedSystemFont(ofSize: 22, weight: .medium)
        label.textColor = NSColor.white.withAlphaComponent(0.92)
        label.alignment = alignment
        label.lineBreakMode = .byTruncatingMiddle
        label.maximumNumberOfLines = 1
        label.translatesAutoresizingMaskIntoConstraints = false
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    }
}

private final class PaletteHeroBadgeView: NSView {
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
        layer?.cornerRadius = 6
        layer?.cornerCurve = .continuous
        layer?.backgroundColor = NSColor.white.withAlphaComponent(0.08).cgColor
        translatesAutoresizingMaskIntoConstraints = false
        setContentHuggingPriority(.required, for: .horizontal)
        // Deliberately NOT .required: a long badge (e.g. the calculator's
        // spelled-out number) must be able to shrink below its intrinsic
        // width so the caller's max-width cap can truncate it instead of
        // overflowing the pane (and the card).
        setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        label.font = .monospacedSystemFont(ofSize: 11, weight: .medium)
        label.textColor = NSColor.white.withAlphaComponent(0.55)
        label.lineBreakMode = .byTruncatingTail
        label.maximumNumberOfLines = 1
        label.translatesAutoresizingMaskIntoConstraints = false
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        addSubview(label)

        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 7),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -7),
            label.topAnchor.constraint(equalTo: topAnchor, constant: 3),
            label.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -3)
        ])
    }
}
