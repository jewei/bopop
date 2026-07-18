import AppKit

extension NSColor {
    /// The one brand accent (DESIGN.md): #aa2b8a light / #ec7fca dark.
    static let bopopAccent = NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(srgbRed: 0xEC/255, green: 0x7F/255, blue: 0xCA/255, alpha: 1)
            : NSColor(srgbRed: 0xAA/255, green: 0x2B/255, blue: 0x8A/255, alpha: 1)
    }
}
