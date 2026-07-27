import AppKit
import BopopKit
import Carbon.HIToolbox
import SwiftUI

/// Resolves a virtual key code to the character it produces on the user's
/// CURRENT keyboard layout, so a saved hotkey still displays correctly after
/// relaunch — when the captured `charactersIgnoringModifiers` is long gone —
/// and on layouts where the US-QWERTY position table is simply wrong.
enum KeyCodeNaming {
    private static let functionKeyCodes: [UInt32: String] = [
        122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6",
        98: "F7", 100: "F8", 101: "F9", 109: "F10", 103: "F11", 111: "F12",
        105: "F13", 107: "F14", 113: "F15", 106: "F16", 64: "F17",
        79: "F18", 80: "F19", 90: "F20"
    ]

    static func functionKeyName(for keyCode: UInt32) -> String? {
        functionKeyCodes[keyCode]
    }

    static func characterName(for keyCode: UInt32) -> String? {
        guard let source = TISCopyCurrentASCIICapableKeyboardLayoutInputSource()?
            .takeRetainedValue(),
            let layoutPointer = TISGetInputSourceProperty(
                source,
                kTISPropertyUnicodeKeyLayoutData
            )
        else {
            return nil
        }
        let layoutData = Unmanaged<CFData>.fromOpaque(layoutPointer)
            .takeUnretainedValue() as Data

        return layoutData.withUnsafeBytes { buffer -> String? in
            guard let header = buffer.baseAddress?.assumingMemoryBound(to: UCKeyboardLayout.self)
            else {
                return nil
            }
            var deadKeyState: UInt32 = 0
            var characters = [UniChar](repeating: 0, count: 4)
            var length = 0
            let status = UCKeyTranslate(
                header,
                UInt16(keyCode),
                UInt16(kUCKeyActionDisplay),
                0, // no modifiers: the bare character this key produces
                UInt32(LMGetKbdType()),
                OptionBits(kUCKeyTranslateNoDeadKeysBit),
                &deadKeyState,
                characters.count,
                &length,
                &characters
            )
            guard status == noErr, length > 0 else {
                return nil
            }
            let name = String(utf16CodeUnits: characters, count: length)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return name.isEmpty ? nil : name.uppercased()
        }
    }
}

struct HotkeyRecorderView: NSViewRepresentable {
    @Binding var hotkey: HotkeyConfig
    @Binding var isRecording: Bool

    /// Keys with no printable character, which no keyboard layout renames.
    /// Everything else is resolved through the CURRENT layout by
    /// `KeyCodeNaming` — a hardcoded table here was US-QWERTY only (so keyCode
    /// 0 read "A" on a Dvorak or AZERTY layout, where it isn't) and covered
    /// neither punctuation nor the function keys, which fell back to the raw
    /// "Key 96".
    private static let unmappedKeyNames: [UInt32: String] = [
        36: "Return", 48: "Tab", 49: "Space", 51: "Delete", 53: "Esc",
        115: "Home", 116: "Page Up", 117: "Forward Delete", 119: "End",
        121: "Page Down", 123: "←", 124: "→", 125: "↓", 126: "↑"
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

    static func unmappedKeyName(for keyCode: UInt32) -> String? {
        unmappedKeyNames[keyCode]
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
        result += capturedKeyName
            ?? unmappedKeyNames[config.keyCode]
            ?? KeyCodeNaming.functionKeyName(for: config.keyCode)
            ?? KeyCodeNaming.characterName(for: config.keyCode)
            ?? "Key \(config.keyCode)"
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
        wantsLayer = true
        layer?.cornerRadius = 6
        layer?.borderWidth = 1
        label.alignment = .center
        label.font = .systemFont(ofSize: NSFont.systemFontSize, weight: .medium)
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            label.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
        refreshColors()
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

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        refreshColors()
    }

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
        refreshColors()
    }

    private func refreshColors() {
        label.textColor = isRecording ? .bopopAccent : .labelColor
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.borderColor = (isRecording
                ? NSColor.bopopAccent
                : NSColor.separatorColor).cgColor
        }
    }

    /// Nil falls back to `HotkeyRecorderView.displayString`'s own resolution,
    /// which is what a relaunch uses anyway — so capture-time and
    /// restored-from-defaults naming agree.
    private static func keyName(for event: NSEvent) -> String? {
        let keyCode = UInt32(event.keyCode)
        if let name = HotkeyRecorderView.unmappedKeyName(for: keyCode) {
            return name
        }
        if let name = KeyCodeNaming.functionKeyName(for: keyCode) {
            return name
        }
        guard let characters = event.charactersIgnoringModifiers,
              !characters.isEmpty else {
            return nil
        }
        return characters.uppercased()
    }
}
