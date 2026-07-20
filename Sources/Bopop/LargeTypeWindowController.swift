import AppKit
import Quartz

/// Full-screen "yell it" overlay toggled by ⌘L: shows the palette's current
/// selection (per `LargeType.text(for:)`) in a huge centered label on a
/// rounded black panel. Dismissed by clicking anywhere, pressing Esc, or
/// ⌘L again — the palette itself stays open behind it.
final class LargeTypeWindowController: NSObject {
    private static let maxPointSize: CGFloat = 96
    private static let minPointSize: CGFloat = 24
    private static let pointSizeStep: CGFloat = 8
    private static let maxLines = 3
    private static let horizontalMargin: CGFloat = 160
    private static let contentPadding: CGFloat = 80
    private static let cornerRadius: CGFloat = 24

    private let panel: LargeTypePanel
    private let textField = NSTextField(labelWithString: "")

    var onDismiss: (() -> Void)?
    /// Fires when key status moves away from this panel to something that
    /// isn't the palette or another Bopop overlay — i.e. the user switched
    /// to a different app while the overlay was up. Unlike `onDismiss`
    /// (user closed the overlay explicitly, palette stays open), this means
    /// the whole palette should hide too. See `LargeTypePanel.resignKey`.
    var onFocusLost: (() -> Void)?

    var isVisible: Bool { panel.isVisible }

    override init() {
        panel = LargeTypePanel(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 300),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        super.init()
        configurePanel()
        configureContent()
        panel.onDismiss = { [weak self] in
            self?.onDismiss?()
        }
        panel.onFocusLost = { [weak self] in
            self?.onFocusLost?()
        }
    }

    private func configurePanel() {
        panel.applyBopopOverlayStyle()
    }

    private func configureContent() {
        guard let contentView = panel.contentView else {
            return
        }
        contentView.wantsLayer = true
        contentView.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.85).cgColor
        contentView.layer?.cornerRadius = Self.cornerRadius

        let click = NSClickGestureRecognizer(target: self, action: #selector(handleClick))
        contentView.addGestureRecognizer(click)

        textField.alignment = .center
        textField.textColor = .white
        textField.maximumNumberOfLines = Self.maxLines
        textField.lineBreakMode = .byWordWrapping
        textField.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(textField)
        NSLayoutConstraint.activate([
            textField.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            textField.centerYAnchor.constraint(equalTo: contentView.centerYAnchor)
        ])
    }

    @objc private func handleClick() {
        onDismiss?()
    }

    /// Sizes to fit `text` at the largest point size (96 → 24, step 8) that
    /// keeps it within 3 lines and `screen.visibleFrame.width - 160`, then
    /// centers the resulting panel on `screen`.
    func show(text: String, on screen: NSScreen) {
        let maxWidth = screen.visibleFrame.width - Self.horizontalMargin
        let font = Self.fittingFont(for: text, maxWidth: maxWidth)
        textField.font = font
        textField.stringValue = text
        textField.preferredMaxLayoutWidth = maxWidth

        let measured = Self.measuredSize(for: text, font: font, maxWidth: maxWidth)
        let width = min(measured.width, maxWidth) + Self.contentPadding
        let height = measured.height + Self.contentPadding
        let frame = NSRect(
            x: screen.visibleFrame.midX - width / 2,
            y: screen.visibleFrame.midY - height / 2,
            width: width,
            height: height
        )
        panel.setFrame(frame, display: true)
        panel.makeKeyAndOrderFront(nil)
    }

    func hide() {
        panel.orderOut(nil)
    }

    /// The largest rounded-bold point size in the shrink sequence whose
    /// wrapped layout (at `maxWidth`) fits within `maxLines`; falls back to
    /// the smallest size in the sequence if even that overflows.
    private static func fittingFont(for text: String, maxWidth: CGFloat) -> NSFont {
        var pointSize = maxPointSize
        while pointSize > minPointSize {
            let candidate = font(ofSize: pointSize)
            if lineCount(for: text, font: candidate, maxWidth: maxWidth) <= maxLines {
                return candidate
            }
            pointSize -= pointSizeStep
        }
        return font(ofSize: minPointSize)
    }

    private static func font(ofSize size: CGFloat) -> NSFont {
        let base = NSFont.systemFont(ofSize: size, weight: .bold)
        guard let rounded = base.fontDescriptor.withDesign(.rounded) else {
            return base
        }
        return NSFont(descriptor: rounded, size: size) ?? base
    }

    private static func lineCount(for text: String, font: NSFont, maxWidth: CGFloat) -> Int {
        layout(for: text, font: font, maxWidth: maxWidth).lines
    }

    private static func measuredSize(for text: String, font: NSFont, maxWidth: CGFloat) -> NSSize {
        layout(for: text, font: font, maxWidth: maxWidth).size
    }

    /// Lays `text` out in an offscreen `NSLayoutManager` at `maxWidth` to
    /// get both the number of wrapped line fragments and the used bounding
    /// size — the two facts the shrink loop and final sizing need.
    private static func layout(
        for text: String,
        font: NSFont,
        maxWidth: CGFloat
    ) -> (lines: Int, size: NSSize) {
        let textStorage = NSTextStorage(string: text, attributes: [.font: font])
        let layoutManager = NSLayoutManager()
        textStorage.addLayoutManager(layoutManager)
        let textContainer = NSTextContainer(
            size: NSSize(width: maxWidth, height: .greatestFiniteMagnitude)
        )
        textContainer.lineFragmentPadding = 0
        layoutManager.addTextContainer(textContainer)

        var lines = 0
        var index = 0
        let glyphCount = layoutManager.numberOfGlyphs
        while index < glyphCount {
            var lineRange = NSRange()
            layoutManager.lineFragmentRect(forGlyphAt: index, effectiveRange: &lineRange)
            lines += 1
            index = NSMaxRange(lineRange)
        }
        let used = layoutManager.usedRect(for: textContainer)
        return (lines, used.size)
    }
}

/// Borderless panel hosting the large-type overlay; Esc calls `onDismiss`
/// the same way a click does, since there's no field editor here to route
/// through (unlike `PalettePanel`).
final class LargeTypePanel: NSPanel {
    var onDismiss: (() -> Void)?
    var onFocusLost: (() -> Void)?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func cancelOperation(_ sender: Any?) {
        onDismiss?()
    }

    /// This panel is key while visible, so ⌘L (unlike Esc/click) reaches it
    /// directly rather than `PalettePanel` — the second ⌘L press that's
    /// supposed to dismiss the overlay has to be caught here instead.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let relevantModifiers = event.relevantModifiers
        if relevantModifiers == .command, event.charactersIgnoringModifiers?.lowercased() == "l" {
            onDismiss?()
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    /// Fires whenever this panel loses key status — both when the user
    /// explicitly dismisses the overlay (click/Esc/⌘L call `onDismiss`,
    /// which hides the panel via `orderOut`, which resigns key as a side
    /// effect) and when the user switches to a different app entirely. The
    /// successor key window isn't known yet during `resignKey` itself, so
    /// — mirroring `PalettePanel.resignKey` — defer one runloop turn and
    /// inspect it then: if the palette (or Quick Look) took key back, this
    /// was the former case and nothing else needs to happen (the explicit
    /// dismiss path already re-keys the palette; see
    /// `PaletteController.connectCallbacks`). Otherwise it's a genuine
    /// focus loss and `onFocusLost` tears the whole palette down too.
    override func resignKey() {
        super.resignKey()
        FocusLossCheck.runDeferred(ownPanel: self) { [weak self] in
            self?.onFocusLost?()
        }
    }
}
