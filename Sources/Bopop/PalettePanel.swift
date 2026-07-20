import AppKit

final class PalettePanel: NSPanel {
    var onResign: (() -> Void)?
    var onCommandCopy: (() -> Bool)?

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
        onResign?()
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let relevantModifiers = event.modifierFlags.intersection([
            .command,
            .shift,
            .option,
            .control
        ])
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
            default:
                break
            }
        }
        return super.performKeyEquivalent(with: event)
    }
}

/// Field editor whose insertion point is a solid block, terminal-style.
/// The default `drawInsertionPoint` fills whatever rect it's handed, so
/// widening the hairline rect is the whole trick; `setNeedsDisplay` must
/// widen its invalidation rect by the same amount or the block leaves
/// trails as the caret moves.
final class BlockCursorTextView: NSTextView {
    var blockCursorWidth: CGFloat = 19

    override func drawInsertionPoint(in rect: NSRect, color: NSColor, turnedOn flag: Bool) {
        var blockRect = rect
        blockRect.size.width = blockCursorWidth
        super.drawInsertionPoint(in: blockRect, color: color, turnedOn: flag)
    }

    override func setNeedsDisplay(_ invalidRect: NSRect, avoidAdditionalLayout flag: Bool) {
        var widened = invalidRect
        widened.size.width += blockCursorWidth
        super.setNeedsDisplay(widened, avoidAdditionalLayout: flag)
    }
}
