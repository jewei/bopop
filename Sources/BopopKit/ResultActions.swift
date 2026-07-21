import Foundation

/// The ordered action list the ⌘K Actions panel shows for a result — and
/// the single source of the primary-action verb the footer displays.
/// Pure logic so the ordering/applicability/dedup rules stay unit-tested.
public nonisolated enum ResultActions {
    public enum Kind: Equatable, Sendable {
        case primary
        case copy
        case reveal
        case quickLook
        case largeType
    }

    public struct ActionItem: Equatable, Sendable {
        public let kind: Kind
        public let title: String
        public let shortcut: String
    }

    /// Lowercase verb for the footer's "↵ open" label; the panel shows it
    /// capitalized as the primary row's title.
    public static func verb(for action: ResultAction) -> String {
        switch action {
        case .openApp, .openFile, .openURL: "open"
        case .copyText: "copy"
        case .clearClipboardHistory: "clear"
        case .runScript, .systemCommand: "run"
        case .enterMode: "select"
        case .downloadTranslation: "download"
        case .revealFile: "reveal"
        }
    }

    public static func items(for result: SearchResult) -> [ActionItem] {
        var items = [ActionItem(
            kind: .primary,
            title: verb(for: result.action).capitalized,
            shortcut: "⏎"
        )]
        // No duplicate row when the primary action already IS a copy.
        if hasCopyAction(result), !isCopyAction(result.action) {
            items.append(ActionItem(kind: .copy, title: "Copy", shortcut: "⌘C"))
        }
        if FilePayload.path(for: result) != nil {
            items.append(ActionItem(kind: .reveal, title: "Reveal in Finder", shortcut: "⌘⏎"))
            items.append(ActionItem(kind: .quickLook, title: "Quick Look", shortcut: "⌘Y"))
        }
        if LargeType.text(for: result) != nil {
            items.append(ActionItem(kind: .largeType, title: "Large Type", shortcut: "⌘L"))
        }
        return items
    }

    /// Moved here from `PaletteController` (which now calls this) so the
    /// panel's copy-dedup rule and the copy-availability check can't drift.
    public static func hasCopyAction(_ result: SearchResult) -> Bool {
        isCopyAction(result.action)
            || result.secondaryActions.contains(where: isCopyAction)
    }

    private static func isCopyAction(_ action: ResultAction) -> Bool {
        if case .copyText = action {
            return true
        }
        return false
    }
}
