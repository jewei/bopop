import AppKit
import Quartz

final class PalettePanel: NSPanel {
    var onResign: (() -> Void)?
    var onCommandCopy: (() -> Bool)?
    var onCommandReveal: (() -> Bool)?
    var onToggleQuickLook: (() -> Bool)?
    var onToggleLargeType: (() -> Bool)?
    var onCommandK: (() -> Bool)?

    /// Set by `PaletteController` (which implements both protocols) so this
    /// panel — the key window while the palette is visible, and thus first
    /// in the responder chain QuickLook consults — can hand control of the
    /// shared `QLPreviewPanel` to it.
    weak var quickLookDataSource: QLPreviewPanelDataSource?
    weak var quickLookDelegate: QLPreviewPanelDelegate?

    private lazy var blockCursorEditor: BlockCursorTextView = {
        // TextKit 1 explicitly: under TextKit 2 (the default since macOS 14)
        // the caret is an NSTextInsertionIndicator subview and
        // drawInsertionPoint(in:) is never called, so the block never draws.
        let editor = BlockCursorTextView(usingTextLayoutManager: false)
        editor.isFieldEditor = true
        return editor
    }()

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    /// The query field gets a custom field editor that draws a fat block
    /// insertion point instead of the hairline bar.
    override func fieldEditor(_ createFlag: Bool, for object: Any?) -> NSText? {
        guard object is NSTextField else {
            return super.fieldEditor(createFlag, for: object)
        }
        return blockCursorEditor
    }

    override func resignKey() {
        super.resignKey()
        // See FocusLossCheck: defers one runloop turn so the successor key
        // window is known, then only treats it as a genuine loss if it
        // isn't one of the app's own overlays (or this panel itself).
        //
        // The `isVisible` condition additionally skips an already-hidden
        // palette: that resign was caused by our own `orderOut` (e.g. from
        // `hide()`'s `panel.orderOut`), not a genuine focus loss — firing
        // `onResign` here would re-enter `hide()` every time the palette
        // closes.
        FocusLossCheck.runDeferred(
            ownPanel: self,
            condition: { [weak self] in self?.isVisible == true }
        ) { [weak self] in
            self?.onResign?()
        }
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let relevantModifiers = event.relevantModifiers
        // There is no menu bar, so Edit-menu key equivalents never fire —
        // the standard editing actions must be routed to the field editor
        // by hand or ⌘V/⌘A/⌘X (and text-selection ⌘C) are dead keys.
        if relevantModifiers == .command {
            switch event.charactersIgnoringModifiers?.lowercased() {
            case "c":
                if onCommandCopy?() == true {
                    return true
                }
                if NSApp.sendAction(#selector(NSText.copy(_:)), to: nil, from: self) {
                    return true
                }
            case "v":
                if NSApp.sendAction(#selector(NSText.paste(_:)), to: nil, from: self) {
                    return true
                }
            case "x":
                if NSApp.sendAction(#selector(NSText.cut(_:)), to: nil, from: self) {
                    return true
                }
            case "a":
                if NSApp.sendAction(#selector(NSText.selectAll(_:)), to: nil, from: self) {
                    return true
                }
            case "\r":
                if onCommandReveal?() == true {
                    return true
                }
            case "y":
                if onToggleQuickLook?() == true {
                    return true
                }
            case "l":
                if onToggleLargeType?() == true {
                    return true
                }
            case "k":
                if onCommandK?() == true {
                    return true
                }
            default:
                break
            }
        }
        return super.performKeyEquivalent(with: event)
    }

    // MARK: - QLPreviewPanel control contract
    //
    // These are an informal NSResponder protocol (declared by QuickLookUI as
    // a category) with no-op default implementations, so overriding them
    // here is how this panel becomes the QLPreviewPanel's data
    // source/delegate whenever it is asked to take control — which happens
    // as long as it's still part of the responder chain of the current key
    // window at the moment `QLPreviewPanel.shared()` is invoked.

    nonisolated override func acceptsPreviewPanelControl(_ panel: QLPreviewPanel!) -> Bool {
        true
    }

    nonisolated override func beginPreviewPanelControl(_ panel: QLPreviewPanel!) {
        MainActor.assumeIsolated {
            panel.dataSource = quickLookDataSource
            panel.delegate = quickLookDelegate
        }
    }

    nonisolated override func endPreviewPanelControl(_ panel: QLPreviewPanel!) {
        MainActor.assumeIsolated {
            panel.dataSource = nil
            panel.delegate = nil
        }
    }
}

/// Field editor whose insertion point is a solid block, terminal-style.
/// The default `drawInsertionPoint` fills whatever rect it's handed, so
/// widening the hairline rect is the core trick; `setNeedsDisplay` must
/// widen its invalidation rect by the same amount or the block leaves
/// trails as the caret moves. When the caret sits ON a character — the
/// placeholder's first letter, or mid-text editing — the block takes that
/// glyph's width and the glyph redraws inverted (dark on the block),
/// like a real terminal cursor.
final class BlockCursorTextView: NSTextView {
    var blockCursorWidth: CGFloat = 19

    private static let inverseInk = NSColor(
        srgbRed: 0x16 / 255,
        green: 0x14 / 255,
        blue: 0x1E / 255,
        alpha: 1
    )

    override func drawInsertionPoint(in rect: NSRect, color: NSColor, turnedOn flag: Bool) {
        var blockRect = rect
        let covered = characterUnderCaret()
        if let covered {
            blockRect.size.width = ceil(covered.size().width)
        } else {
            blockRect.size.width = blockCursorWidth
        }
        super.drawInsertionPoint(in: blockRect, color: color, turnedOn: flag)
        guard flag, let covered else {
            return
        }
        var inverted = AttributedString(covered)
        inverted.foregroundColor = Self.inverseInk
        NSAttributedString(inverted).draw(at: blockRect.origin)
    }

    override func setNeedsDisplay(_ invalidRect: NSRect, avoidAdditionalLayout flag: Bool) {
        var widened = invalidRect
        widened.size.width += max(blockCursorWidth, 40)
        super.setNeedsDisplay(widened, avoidAdditionalLayout: flag)
    }

    /// The single character the caret visually covers, with its original
    /// attributes: the character at the insertion index while editing, or
    /// the placeholder's first character when the field is empty.
    private func characterUnderCaret() -> NSAttributedString? {
        let selection = selectedRange()
        guard selection.length == 0 else {
            return nil
        }
        if let textStorage, textStorage.length > 0, selection.location < textStorage.length {
            return textStorage.attributedSubstring(
                from: NSRange(location: selection.location, length: 1)
            )
        }
        if string.isEmpty,
           let field = delegate as? NSTextField,
           let placeholder = field.placeholderAttributedString,
           placeholder.length > 0 {
            return placeholder.attributedSubstring(from: NSRange(location: 0, length: 1))
        }
        return nil
    }
}
