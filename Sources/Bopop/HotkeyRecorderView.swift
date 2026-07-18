import AppKit
import BopopKit
import SwiftUI

struct HotkeyRecorderView: NSViewRepresentable {
    @Binding var hotkey: HotkeyConfig
    @Binding var isRecording: Bool

    private static let keyNames: [UInt32: String] = [
        0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G",
        6: "Z", 7: "X", 8: "C", 9: "V", 11: "B", 12: "Q",
        13: "W", 14: "E", 15: "R", 16: "Y", 17: "T",
        18: "1", 19: "2", 20: "3", 21: "4", 22: "6", 23: "5",
        25: "9", 26: "7", 28: "8", 29: "0", 31: "O", 32: "U",
        34: "I", 35: "P", 37: "L", 38: "J", 40: "K", 45: "N",
        46: "M", 36: "Return", 48: "Tab", 49: "Space", 51: "Delete",
        53: "Esc", 123: "←", 124: "→", 125: "↓", 126: "↑"
    ]

    func makeCoordinator() -> Coordinator {
        Coordinator(hotkey: $hotkey, isRecording: $isRecording)
    }

    func makeNSView(context: Context) -> RecorderNSView {
        let view = RecorderNSView()
        view.onBeginRecording = context.coordinator.beginRecording
        view.onRecord = context.coordinator.record
        view.onCancel = context.coordinator.cancel
        view.update(config: hotkey, isRecording: isRecording)
        return view
    }

    func updateNSView(_ nsView: RecorderNSView, context: Context) {
        context.coordinator.hotkey = $hotkey
        context.coordinator.isRecording = $isRecording
        nsView.update(config: hotkey, isRecording: isRecording)
    }

    static func displayString(
        for config: HotkeyConfig,
        capturedKeyName: String? = nil
    ) -> String {
        var result = ""
        if config.modifiers.contains(.control) {
            result += "⌃"
        }
        if config.modifiers.contains(.option) {
            result += "⌥"
        }
        if config.modifiers.contains(.shift) {
            result += "⇧"
        }
        if config.modifiers.contains(.command) {
            result += "⌘"
        }
        result += capturedKeyName ?? keyNames[config.keyCode] ?? "Key \(config.keyCode)"
        return result
    }

    final class Coordinator {
        var hotkey: Binding<HotkeyConfig>
        var isRecording: Binding<Bool>

        init(hotkey: Binding<HotkeyConfig>, isRecording: Binding<Bool>) {
            self.hotkey = hotkey
            self.isRecording = isRecording
        }

        func beginRecording() {
            isRecording.wrappedValue = true
        }

        func record(_ config: HotkeyConfig) {
            hotkey.wrappedValue = config
            isRecording.wrappedValue = false
        }

        func cancel() {
            isRecording.wrappedValue = false
        }
    }
}

final class RecorderNSView: NSView {
    var onBeginRecording: (() -> Void)?
    var onRecord: ((HotkeyConfig) -> Void)?
    var onCancel: (() -> Void)?

    override var acceptsFirstResponder: Bool { true }

    private static let supportedModifiers: NSEvent.ModifierFlags = [
        .control, .option, .shift, .command
    ]
    private static let requiredModifiers: NSEvent.ModifierFlags = [
        .control, .option, .command
    ]

    private let label = NSTextField(labelWithString: "")
    private var config = HotkeyConfig.default
    private var isRecording = false
    private var capturedKeyName: String?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        label.alignment = .center
        label.font = .systemFont(ofSize: NSFont.systemFontSize, weight: .medium)
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            label.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        isRecording = true
        refreshLabel()
        onBeginRecording?()
    }

    override func keyDown(with event: NSEvent) {
        guard isRecording else {
            super.keyDown(with: event)
            return
        }

        let modifiers = event.modifierFlags
            .intersection(.deviceIndependentFlagsMask)
            .intersection(Self.supportedModifiers)
        if event.keyCode == 53, modifiers.isEmpty {
            isRecording = false
            refreshLabel()
            onCancel?()
            return
        }
        guard !modifiers.intersection(Self.requiredModifiers).isEmpty else {
            NSSound.beep()
            return
        }

        let hotkeyModifiers = HotkeyConfig.Modifiers(rawValue: modifiers.rawValue)
        let newConfig = HotkeyConfig(
            keyCode: UInt32(event.keyCode),
            modifiers: hotkeyModifiers
        )
        config = newConfig
        capturedKeyName = Self.keyName(for: event)
        isRecording = false
        refreshLabel()
        onRecord?(newConfig)
    }

    override func resignFirstResponder() -> Bool {
        let didResign = super.resignFirstResponder()
        if didResign, isRecording {
            isRecording = false
            refreshLabel()
            onCancel?()
        }
        return didResign
    }

    override func flagsChanged(with event: NSEvent) {}

    func update(config: HotkeyConfig, isRecording: Bool) {
        if config != self.config {
            capturedKeyName = nil
        }
        self.config = config
        self.isRecording = isRecording
        refreshLabel()
    }

    private func refreshLabel() {
        label.stringValue = isRecording
            ? "Type new shortcut…"
            : HotkeyRecorderView.displayString(
                for: config,
                capturedKeyName: capturedKeyName
            )
    }

    private static func keyName(for event: NSEvent) -> String? {
        switch event.keyCode {
        case 49: return "Space"
        case 36: return "Return"
        case 48: return "Tab"
        case 51: return "Delete"
        case 53: return "Esc"
        case 123: return "←"
        case 124: return "→"
        case 125: return "↓"
        case 126: return "↑"
        default:
            guard let characters = event.charactersIgnoringModifiers,
                  !characters.isEmpty else {
                return nil
            }
            return characters.uppercased()
        }
    }
}
