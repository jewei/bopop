import Foundation

/// The ordered action list the ⌘K Actions panel shows for a result — and
/// the single source of the primary-action verb the footer displays.
/// Pure logic so the ordering/applicability/dedup rules stay unit-tested.
public nonisolated enum ResultActions {
    public enum Kind: Equatable, Sendable {
        case primary
        case copy
        case pin
        case quit
        case hide
        case reveal
        case quickLook
        case largeType
    }

    public struct ActionItem: Equatable, Sendable {
        public let kind: Kind
        public let title: String
        /// `nil` for rows the panel lists without a direct key of their own —
        /// modelled as absence rather than "" so the row view can skip
        /// building a keycap it would never show.
        public let shortcut: String?
    }

    /// Lowercase verb for the footer's "↵ open" label; the panel shows it
    /// capitalized as the primary row's title.
    public static func verb(for action: ResultAction) -> String {
        switch action {
        case .openApp, .openFile, .openURL: "open"
        case .copyText: "copy"
        case .clearClipboardHistory: "clear"
        case .pinClipboard: "pin"
        case .unpinClipboard: "unpin"
        case .quitApp: "quit"
        case .hideResult: "hide"
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
        if let pin = pinAction(in: result) {
            items.append(ActionItem(
                kind: .pin,
                title: pinTitle(for: pin),
                shortcut: nil
            ))
        }
        // No duplicate row when the primary action already IS a copy.
        if hasCopyAction(result), !isCopyAction(result.action) {
            items.append(ActionItem(kind: .copy, title: "Copy", shortcut: "⌘C"))
        }
        // Panel-only, with no chord of its own: ⌘⏎ is already Reveal in Finder
        // for exactly the rows that can be quit, and quitting an app is not
        // something to put one keystroke away from a typo.
        if hasQuitAction(result) {
            items.append(ActionItem(kind: .quit, title: "Quit", shortcut: nil))
        }
        if hideAction(in: result) != nil {
            items.append(ActionItem(kind: .hide, title: "Hide from Results", shortcut: nil))
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

    public static func hasPinAction(_ result: SearchResult) -> Bool {
        pinAction(in: result) != nil
    }

    public static func hasQuitAction(_ result: SearchResult) -> Bool {
        quitAction(in: result) != nil
    }

    public static func hideAction(in result: SearchResult) -> ResultAction? {
        result.secondaryActions.first { action in
            if case .hideResult = action {
                return true
            }
            return false
        }
    }

    public static func quitAction(in result: SearchResult) -> ResultAction? {
        result.secondaryActions.first { action in
            if case .quitApp = action {
                return true
            }
            return false
        }
    }

    public static func pinAction(in result: SearchResult) -> ResultAction? {
        result.secondaryActions.first(where: isPinAction)
    }

    private static func isCopyAction(_ action: ResultAction) -> Bool {
        if case .copyText = action {
            return true
        }
        return false
    }

    private static func isPinAction(_ action: ResultAction) -> Bool {
        switch action {
        case .pinClipboard, .unpinClipboard: true
        default: false
        }
    }

    private static func pinTitle(for action: ResultAction) -> String {
        switch action {
        case .unpinClipboard: "Unpin"
        default: "Pin"
        }
    }
}
