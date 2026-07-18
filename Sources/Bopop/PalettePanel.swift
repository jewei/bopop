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
        if relevantModifiers == .command,
           event.charactersIgnoringModifiers?.lowercased() == "c",
           onCommandCopy?() == true {
            return true
        }
        return super.performKeyEquivalent(with: event)
    }
}
