import Foundation

/// The on-disk path a result refers to, if any — drives Reveal in Finder,
/// Quick Look, and Large Type's path fallback.
public nonisolated enum FilePayload {
    public static func path(for result: SearchResult?) -> String? {
        guard let result else { return nil }
        for action in [result.action] + result.secondaryActions {
            switch action {
            case .openFile(let path), .openApp(let path), .revealFile(let path):
                return path
            default:
                continue
            }
        }
        return nil
    }
}
