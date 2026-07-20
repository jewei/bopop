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
