import Foundation

public nonisolated struct HotkeyConfig: Equatable, Codable, Sendable {
    public var keyCode: UInt32
    public var modifiers: Modifiers

    public init(keyCode: UInt32, modifiers: Modifiers) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    public nonisolated struct Modifiers: OptionSet, Codable, Equatable, Sendable {
        public let rawValue: UInt

        public init(rawValue: UInt) {
            self.rawValue = rawValue
        }

        public static let command = Modifiers(rawValue: 1 << 20)
        public static let shift = Modifiers(rawValue: 1 << 17)
        public static let option = Modifiers(rawValue: 1 << 19)
        public static let control = Modifiers(rawValue: 1 << 18)
    }

    public static let `default` = HotkeyConfig(keyCode: 49, modifiers: [.command])

    public var carbonModifiers: UInt32 {
        var result: UInt32 = 0
        if modifiers.contains(.command) {
            result |= 0x100
        }
        if modifiers.contains(.shift) {
            result |= 0x200
        }
        if modifiers.contains(.option) {
            result |= 0x800
        }
        if modifiers.contains(.control) {
            result |= 0x1000
        }
        return result
    }

    public func save(to defaults: UserDefaults) {
        defaults.set(keyCode, forKey: "hotkeyKeyCode")
        defaults.set(modifiers.rawValue, forKey: "hotkeyModifiers")
    }

    public static func load(from defaults: UserDefaults) -> HotkeyConfig {
        guard
            let keyCode = defaults.object(forKey: "hotkeyKeyCode") as? NSNumber,
            let modifiers = defaults.object(forKey: "hotkeyModifiers") as? NSNumber
        else {
            return .default
        }

        return HotkeyConfig(
            keyCode: keyCode.uint32Value,
            modifiers: Modifiers(rawValue: modifiers.uintValue)
        )
    }
}
