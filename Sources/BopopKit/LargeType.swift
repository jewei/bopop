import Foundation

public nonisolated enum LargeType {
    /// What ⌘L blows up full-screen: the copy payload, else the hero's answer
    /// pane, else the file name. Results with none of those have no large-type
    /// representation.
    public static func text(for result: SearchResult?) -> String? {
        guard let result else { return nil }
        for action in [result.action] + result.secondaryActions {
            if case .copyText(let text) = action {
                return text
            }
        }
        if let hero = result.hero {
            return hero.right
        }
        if let path = FilePayload.path(for: result) {
            return (path as NSString).lastPathComponent
        }
        return nil
    }
}
