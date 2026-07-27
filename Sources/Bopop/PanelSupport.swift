import AppKit
import Quartz

/// Checks, after a one-runloop-turn deferral, whether a resigned-key
/// window's successor is a genuine focus loss rather than one of Bopop's
/// own overlays trading key status among themselves.
///
/// The successor key window isn't known yet at the moment key status is
/// actually resigned (whether that's observed via `resignKey` itself, as
/// `PalettePanel`/`LargeTypePanel` do, or via
/// `NSWindow.didResignKeyNotification`, as `QLPreviewPanel` — a system
/// singleton that can't be subclassed — requires), so every site that needs
/// to tell "genuine focus loss" apart from "another Bopop overlay (or this
/// window itself) took key back" defers one turn and asks this the same
/// question against the same allowlist.
enum FocusLossCheck {
    /// `ownPanel` is the window this check runs on behalf of, so regaining
    /// its own key status also reads as a non-loss. `condition` gates
    /// whether a genuine loss should even fire `onFocusLoss` — e.g.
    /// `PalettePanel` uses it to skip an already-hidden panel's resign
    /// (caused by its own `orderOut`, not a real focus change).
    static func runDeferred(
        ownPanel: NSWindow?,
        condition: @escaping () -> Bool = { true },
        onFocusLoss: @escaping () -> Void
    ) {
        DispatchQueue.main.async {
            switch NSApp.keyWindow {
            case ownPanel, is PalettePanel, is LargeTypePanel, is QLPreviewPanel:
                return
            default:
                if condition() {
                    onFocusLoss()
                }
            }
        }
    }
}

/// Bopop is an LSUIElement (`.accessory`) app that gets promoted to
/// `.regular` whenever something needs Dock/Cmd-Tab presence — Sparkle's
/// update UI, the Settings window. Both promoters have to drop it back when
/// no window needs that any more: leaving it `.regular` strands a Dock icon
/// for a background agent, and dropping it while a window is still up
/// strands that window without focus.
///
/// This is the single answer to "does anything still need focus presence?".
/// It previously existed twice, with different criteria — `AppUpdater`
/// matched a window by the literal title "Bopop Settings" (so a rename would
/// silently reintroduce the stranded-window bug the check exists to prevent),
/// while `SettingsWindowController` used a structural test.
enum ActivationPolicy {
    /// Deferred one runloop turn because every caller runs *while* a window
    /// is closing: at the moment of the call it can still be in
    /// `NSApp.windows` and still report `isVisible`.
    ///
    /// `excluding` is the window the caller is itself closing, for callers
    /// that run before it leaves the list.
    static func restoreAccessoryWhenNothingNeedsFocus(excluding excluded: NSWindow? = nil) {
        Task { @MainActor in
            let needsFocus = NSApp.windows.contains { window in
                window !== excluded
                    && window.isVisible
                    // Overlays (palette, large type, actions) are panels and
                    // never justify Dock presence.
                    && !(window is NSPanel)
                    // Excludes the offscreen, alpha-0 AppleTranslator host,
                    // which is borderless and so can't become key.
                    && window.canBecomeKey
            }
            if !needsFocus {
                NSApp.setActivationPolicy(.accessory)
            }
        }
    }
}

extension NSPanel {
    /// Shared chrome for Bopop's borderless, status-level overlay panels
    /// (palette + large-type): floats above everything, joins every Space
    /// including full-screen ones, stays out of the window-cycling UI, and
    /// paints nothing of its own — each panel's own layer-backed content
    /// view supplies the visuals via the transparent/opaque-false
    /// background. `appearance` and `isMovableByWindowBackground` are
    /// intentionally NOT part of this shared style: the two panels
    /// genuinely differ on them (only the palette is user-draggable and
    /// forces dark aqua).
    func applyBopopOverlayStyle() {
        level = .statusBar
        collectionBehavior = [
            .canJoinAllSpaces,
            .fullScreenAuxiliary,
            .transient,
            .ignoresCycle
        ]
        isFloatingPanel = true
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
        animationBehavior = .none
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
    }
}

extension NSEvent {
    /// The modifier flags Bopop's key-equivalent handling cares about,
    /// narrowed from `modifierFlags` — which also carries incidental state
    /// (e.g. caps lock, function key) that would otherwise defeat a clean
    /// `== .command` comparison.
    var relevantModifiers: NSEvent.ModifierFlags {
        modifierFlags.intersection([.command, .shift, .option, .control])
    }
}
