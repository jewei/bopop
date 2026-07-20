import AppKit

final class PalettePanel: NSPanel {
    var onResign: (() -> Void)?
    var onCommandCopy: (() -> Bool)?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

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
