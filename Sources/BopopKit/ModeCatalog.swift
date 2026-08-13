import Foundation

/// One source of truth for mode presentation metadata. Provider instances
/// remain in the composition root because they have runtime dependencies;
/// labels, tab placement and surface shape do not.
public struct ModeDescriptor: Equatable, Sendable {
    public enum TabPlacement: Equatable, Sendable {
        case resting
        case transient
    }

    public let mode: Mode
    public let title: String
    public let symbolName: String
    public let tabPlacement: TabPlacement
    public let presentation: PalettePresentation
}

public extension Mode {
    static let descriptors: [ModeDescriptor] = [
        ModeDescriptor(
            mode: .general, title: "All", symbolName: "square.grid.2x2",
            tabPlacement: .resting, presentation: .list
        ),
        ModeDescriptor(
            mode: .apps, title: "Apps", symbolName: "app",
            tabPlacement: .resting, presentation: .list
        ),
        ModeDescriptor(
            mode: .fileSearch, title: "Files", symbolName: "folder",
            tabPlacement: .resting, presentation: .list
        ),
        ModeDescriptor(
            mode: .clipboard, title: "Clipboard", symbolName: "doc.on.clipboard",
            tabPlacement: .resting, presentation: .list
        ),
        ModeDescriptor(
            mode: .emoji, title: "Emoji", symbolName: "face.smiling",
            tabPlacement: .resting, presentation: .grid
        ),
        ModeDescriptor(
            mode: .translation, title: "Translate", symbolName: "character.bubble",
            tabPlacement: .resting, presentation: .list
        ),
        ModeDescriptor(
            mode: .snippets, title: "Snippets", symbolName: "text.quote",
            tabPlacement: .transient, presentation: .list
        )
    ]

    static let restingModes = descriptors.compactMap {
        $0.tabPlacement == .resting ? $0.mode : nil
    }

    private static let descriptorsByMode = Dictionary(
        uniqueKeysWithValues: descriptors.map { ($0.mode, $0) }
    )

    var descriptor: ModeDescriptor {
        guard let descriptor = Self.descriptorsByMode[self] else {
            preconditionFailure("Mode catalog is missing \(rawValue)")
        }
        return descriptor
    }
}
