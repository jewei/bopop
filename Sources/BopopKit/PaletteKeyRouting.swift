import Foundation

/// A key the palette understands, already decoded from AppKit.
///
/// `NSEvent` chords and `NSResponder` selectors are two different spellings of
/// the same intent, and both used to carry their own copy of the routing
/// rules. Decoding stays in the adapter; what a key *means* is decided here.
public enum PaletteKey: Equatable, Sendable, CaseIterable {
    case up
    case down
    case left
    case right
    case tab
    case backTab
    case enter
    case escape
    case commandCopy
    /// ⌘⏎
    case commandReveal
    /// ⌘Y
    case commandQuickLook
    /// ⌘L
    case commandLargeType
    /// ⌘K
    case commandActions
    /// ⌘,
    case commandSettings
    /// ⌘W
    case commandClose
}

/// Which of the palette's own overlays are up. The only thing the routing
/// decision needs from AppKit, and it is three booleans rather than three
/// window references.
public struct PaletteOverlays: Equatable, Sendable {
    public let actionsPanelIsVisible: Bool
    public let quickLookIsVisible: Bool
    public let largeTypeIsVisible: Bool

    public init(
        actionsPanelIsVisible: Bool = false,
        quickLookIsVisible: Bool = false,
        largeTypeIsVisible: Bool = false
    ) {
        self.actionsPanelIsVisible = actionsPanelIsVisible
        self.quickLookIsVisible = quickLookIsVisible
        self.largeTypeIsVisible = largeTypeIsVisible
    }
}

/// What the adapter should do with a key.
public enum PaletteKeyOutcome: Equatable, Sendable {
    case perform(PaletteKeyAction)
    /// Not the palette's key. The adapter must report it unhandled so AppKit
    /// carries on — this is what lets ← and → move the caret, and ⌘C copy
    /// selected text out of the query field. Reporting it handled instead
    /// silently swallows the keystroke.
    case passThrough
}

public enum PaletteKeyAction: Equatable, Sendable {
    case moveSelection(PaletteSelectionMove)
    case cycleTab(shift: Bool)
    case runFocused
    case escape
    case actionsPanelMove(Int)
    case actionsPanelRunSelected
    case actionsPanelDismiss
    case actionsPanelRun(ResultActions.Kind)
    case toggleActionsPanel
    case toggleQuickLook
    case toggleLargeType
    case showSettings
    case closePalette
    /// Handled, but deliberately does nothing — swallowing the key is the
    /// behaviour. ←/→ in the grid while the actions panel is open would
    /// otherwise move the result selection out from under the panel, leaving
    /// it showing a stale result's actions.
    case swallow
}

public extension PaletteState {
    /// Decides what a key means, without changing anything.
    ///
    /// Kept pure so the whole matrix is a table test. The rules it replaces
    /// lived in three files — the ⌘-chord table on the panel, a closure per
    /// chord on the controller, and the selector switch — and the ones that
    /// mattered most were duplicated: the overlay-dismiss-beats-panel-gating
    /// precedence was written twice, once for Quick Look and once for Large
    /// Type, and the grid/text ←→ asymmetry was stated three times, twice as
    /// prose.
    func route(_ key: PaletteKey, overlays: PaletteOverlays) -> PaletteKeyOutcome {
        if let outcome = routeCommand(key, overlays: overlays) {
            return outcome
        }
        if overlays.actionsPanelIsVisible,
           let outcome = routeWhileActionsPanelIsOpen(key) {
            return outcome
        }
        return routeNavigation(key)
    }
}

private extension PaletteState {
    /// A ⌘-chord, or nil if this key is not one.
    func routeCommand(
        _ key: PaletteKey,
        overlays: PaletteOverlays
    ) -> PaletteKeyOutcome? {
        switch key {
        case .commandCopy:
            return panelAction(.copy, if: overlays.actionsPanelIsVisible)
        case .commandReveal:
            return panelAction(.reveal, if: overlays.actionsPanelIsVisible)
        case .commandQuickLook:
            // The dismiss wins over the panel gating: if the overlay is
            // already up, the same key closes it whether or not the actions
            // panel also happens to be open.
            if overlays.quickLookIsVisible {
                return .perform(.toggleQuickLook)
            }
            return panelAction(.quickLook, if: overlays.actionsPanelIsVisible)
        case .commandLargeType:
            if overlays.largeTypeIsVisible {
                return .perform(.toggleLargeType)
            }
            return panelAction(.largeType, if: overlays.actionsPanelIsVisible)
        case .commandActions:
            return .perform(.toggleActionsPanel)
        case .commandSettings:
            return .perform(.showSettings)
        case .commandClose:
            return .perform(.closePalette)
        case .up, .down, .left, .right, .tab, .backTab, .enter, .escape:
            return nil
        }
    }

    /// Panel-only shortcuts act on the focused result, and only while the
    /// actions panel is open and actually offers that action. Anything else
    /// passes through — for ⌘C that reaches the field editor's text copy,
    /// which stays the behaviour whenever the panel is closed.
    func panelAction(
        _ kind: ResultActions.Kind,
        if panelIsVisible: Bool
    ) -> PaletteKeyOutcome {
        guard panelIsVisible, offersAction(kind) else {
            return .passThrough
        }
        return .perform(.actionsPanelRun(kind))
    }

    func offersAction(_ kind: ResultActions.Kind) -> Bool {
        guard let focused = focusedResult else {
            return false
        }
        return ResultActions.items(for: focused).contains { $0.kind == kind }
    }

    /// Keys the open actions panel claims, or nil to let normal handling run —
    /// ⇥ still cycles the tab row, and the resulting query change closes the
    /// panel on its own.
    func routeWhileActionsPanelIsOpen(_ key: PaletteKey) -> PaletteKeyOutcome? {
        switch key {
        case .up:
            return .perform(.actionsPanelMove(-1))
        case .down:
            return .perform(.actionsPanelMove(1))
        case .enter:
            return .perform(.actionsPanelRunSelected)
        case .escape:
            return .perform(.actionsPanelDismiss)
        case .left, .right:
            // Swallowed in the grid so the tiles don't move under the panel;
            // in text mode these are caret motion and must pass through.
            return isGridPresentation ? .perform(.swallow) : nil
        default:
            return nil
        }
    }

    func routeNavigation(_ key: PaletteKey) -> PaletteKeyOutcome {
        switch key {
        case .up:
            return .perform(.moveSelection(.up))
        case .down:
            return .perform(.moveSelection(.down))
        case .left:
            // The one asymmetry: in the grid these move the selection, in the
            // list they belong to the caret.
            return isGridPresentation ? .perform(.moveSelection(.left)) : .passThrough
        case .right:
            return isGridPresentation ? .perform(.moveSelection(.right)) : .passThrough
        case .tab:
            return .perform(.cycleTab(shift: false))
        case .backTab:
            return .perform(.cycleTab(shift: true))
        case .enter:
            return .perform(.runFocused)
        case .escape:
            return .perform(.escape)
        case .commandCopy, .commandReveal, .commandQuickLook, .commandLargeType,
             .commandActions, .commandSettings, .commandClose:
            return .passThrough
        }
    }
}
