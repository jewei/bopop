import Foundation

public nonisolated enum LargeType {
    /// The overlay renders at most 3 lines at 24pt or larger, so this is well
    /// past anything it can display. Without a cap the full copy payload — up
    /// to `ClipboardStore.maximumTextSize`, 100 KB — reached the overlay's
    /// offscreen sizing pass, which laid all of it out ten times over (0.34 s
    /// of main-thread work, measured) and returned an 18,000-point panel
    /// height for text that renders as three lines.
    public static let characterLimit = 500

    /// What ⌘L blows up full-screen: the copy payload, else the hero's answer
    /// pane, else the file name. Results with none of those have no large-type
    /// representation.
    public static func text(for result: SearchResult?) -> String? {
        guard let result else { return nil }
        for action in [result.action] + result.secondaryActions {
            if case .copyText(let text) = action {
                return capped(text)
            }
        }
        if let hero = result.hero {
            return capped(hero.right)
        }
        if let path = FilePayload.path(for: result) {
            return (path as NSString).lastPathComponent
        }
        return nil
    }

    private static func capped(_ text: String) -> String {
        guard text.count > characterLimit else {
            return text
        }
        return String(text.prefix(characterLimit)) + "…"
    }
}
