import Foundation

public nonisolated enum CategoryBadge {
    public static func text(for result: SearchResult) -> String? {
        if let badge = result.badge {
            return badge
        }

        switch result.providerID {
        case .apps: return "Apps"
        case .files: return "Files"
        case .clipboard: return "Clipboard"
        case .emoji: return "Emoji"
        case .webSearch: return "Web"
        default: return nil
        }
    }
}
