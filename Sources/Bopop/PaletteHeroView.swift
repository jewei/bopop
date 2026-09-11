import AppKit
import BopopKit

/// Renders `HeroContent` as a "before → after" card: a source pane, an arrow
/// with an optional note, and a target pane — mirrored left/right. Sits
/// between the query field and the results list whenever the top-ranked
/// result carries hero content (see `PaletteState`, which splits it off the rows).
final class PaletteHeroView: NSView {
    private static let horizontalInset: CGFloat = 20
    private static let paneGap: CGFloat = 16
    private static let noteMaxWidth: CGFloat = 140

    /// Sizes the value labels shrink through so an opaque payload fits the two
    /// lines the card has room for. Only `rightWrapsByCharacter` heroes shrink;
    /// prose heroes stay at the first entry, exactly as before.
    private static let valueFontSizes: [CGFloat] = [22, 17, 13, 11]
    private static let valueLineLimit = 2

    private let leftValueLabel = NSTextField(labelWithString: "")
    private let rightValueLabel = NSTextField(labelWithString: "")
    /// The payload awaiting a fitted font. Non-nil only for payload heroes —
    /// the size depends on the laid-out pane width, which `configure` does not
    /// yet know, so the decision is deferred to `layout()`.
    private var shrinkToFitPayload: String?
    private var selected = false

    /// The card draws its selection itself rather than through AppKit's
    /// selection machinery, so there is nothing else a test can read back.
    var isSelectedForTesting: Bool { selected }
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
        // Re-applied per configure, not set once: the same view is reused
        // across heroes, so a password would otherwise leave character
        // wrapping behind for the next timezone description to inherit.
        rightValueLabel.lineBreakMode = hero.rightWrapsByCharacter
            ? .byCharWrapping
            : .byWordWrapping
        shrinkToFitPayload = hero.rightWrapsByCharacter ? hero.right : nil
        if !hero.rightWrapsByCharacter {
            rightValueLabel.font = Self.valueFont(ofSize: Self.valueFontSizes[0])
        }
        needsLayout = true

        let accessibilityText = [hero.left, hero.leftBadge, hero.right, hero.rightBadge, hero.note]
            .compactMap { $0 }
            .joined(separator: ", ")
        setAccessibilityLabel(accessibilityText)
    }

    /// Marks the card as the thing ⏎ will act on.
    ///
    /// The card competes with the rows below it for exactly one Return, and
    /// until this existed the palette answered "which one?" with nothing at
    /// all: `PaletteController.applyFocus` deselects the table when focus is
    /// `.hero`, so no row was lit and neither was the card. Harmless where the
    /// hero IS the only answer (a calculation, a conversion), but the password
    /// generator puts four near-identical payloads on screen at once and the
    /// only way to see the target was to press ↓ — which moved it.
    func setSelected(_ isSelected: Bool) {
        guard selected != isSelected else {
            return
        }
        selected = isSelected
        updateSelectionStyle()
    }

    /// Deliberately the same fill and stroke as `PaletteRowView.drawSelection`.
    /// "This owns ⏎" has to read identically whether it lands on a row or on
    /// the card, so these two are the same treatment on different geometry —
    /// the card keeps its own 10 pt radius rather than the row capsule's.
    private func updateSelectionStyle() {
        CATransaction.begin()
        // No decorative motion (docs/design-system.md), and selection moves
        // under held arrow keys — a cross-fade per keystroke would smear.
        CATransaction.setDisableActions(true)
        layer?.backgroundColor = selected
            ? NSColor.bopopAccent.withAlphaComponent(0.14).cgColor
            : NSColor.white.withAlphaComponent(0.04).cgColor
        layer?.borderWidth = selected ? 1 : 0
        layer?.borderColor = selected
            ? NSColor.bopopAccent.withAlphaComponent(0.30).cgColor
            : nil
        CATransaction.commit()
    }

    /// Applies the fitted font once the pane width is known.
    ///
    /// Converges: the pane's width comes from the constraint chain rather than
    /// from its content (value labels have `.defaultLow` compression
    /// resistance), so the chosen size cannot change the width that chose it.
    /// A second pass computes the same answer, finds the font already set, and
    /// stops.
    override func layout() {
        super.layout()
        guard let payload = shrinkToFitPayload else {
            return
        }
        let fitted = Self.valueFont(
            ofSize: Self.fittingSize(for: payload, width: rightValueLabel.frame.width)
        )
        if rightValueLabel.font != fitted {
            rightValueLabel.font = fitted
        }
    }

    /// The largest size in the ladder that renders `payload` within the line
    /// limit, or the smallest size if none of them do — a value too long for
    /// even 11pt still truncates, but it truncates having tried.
    static func fittingSize(for payload: String, width: CGFloat) -> CGFloat {
        guard width > 0 else {
            return valueFontSizes[0]
        }
        let style = NSMutableParagraphStyle()
        style.lineBreakMode = .byCharWrapping
        for size in valueFontSizes {
            let font = valueFont(ofSize: size)
            let needed = (payload as NSString).boundingRect(
                with: NSSize(width: width, height: .greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin],
                attributes: [.font: font, .paragraphStyle: style]
            )
            let lines = Int((needed.height / font.boundingRectForFont.height).rounded(.up))
            if lines <= valueLineLimit {
                return size
            }
        }
        return valueFontSizes[valueFontSizes.count - 1]
    }

    static func valueFont(ofSize size: CGFloat) -> NSFont {
        .monospacedSystemFont(ofSize: size, weight: .medium)
    }

    private func configureView() {
        wantsLayer = true
        // This lives INSIDE the already-masked panel content view, so a plain
        // layer corner radius is fine here — the maskImage gotcha only
        // applies to the panel's own NSVisualEffectView (docs/gotchas.md #5).
        layer?.cornerRadius = 10
        layer?.cornerCurve = .continuous
        // Owns the unselected background too, so the two states live in one
        // place rather than here and in `setSelected`.
        updateSelectionStyle()
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
        label.font = Self.valueFont(ofSize: Self.valueFontSizes[0])
        label.textColor = NSColor.white.withAlphaComponent(0.92)
        label.alignment = alignment
        // Long values (timezone descriptions) wrap to a second line instead
        // of truncating; anything longer than two lines truncates at the tail.
        label.lineBreakMode = .byWordWrapping
        label.maximumNumberOfLines = 2
        label.cell?.truncatesLastVisibleLine = true
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
