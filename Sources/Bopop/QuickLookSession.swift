import AppKit
import Quartz

/// The part of Quick Look lifecycle that matters to focus decisions. A plain
/// visibility Boolean loses the crucial distinction between opening, stable,
/// and resigning; in particular, a visible panel may be resigning because the
/// user switched to another application.
enum FocusHandoffState: Equatable {
    case stable
    case openingQuickLook
    case resolvingQuickLookResign
}

/// Owns the shared preview panel's lifecycle and notification wiring. Callers
/// ask this object to show/hide/reload instead of repeating singleton existence
/// and visibility walks throughout PaletteController.
@MainActor
final class QuickLookSession {
    var onResign: (() -> Void)?
    var onExternalApplicationActivated: (() -> Void)?

    private(set) var focusHandoffState: FocusHandoffState = .stable
    private var didBecomeKeyObserver: NotificationToken?
    private var didResignKeyObserver: NotificationToken?
    private let workspaceNotificationCenter = NSWorkspace.shared.notificationCenter
    private var workspaceActivationObserver: NSObjectProtocol?

    init() {
        workspaceActivationObserver = workspaceNotificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self,
                      self.isVisible || self.focusHandoffState != .stable,
                      NSWorkspace.shared.frontmostApplication?.processIdentifier
                        != ProcessInfo.processInfo.processIdentifier
                else {
                    return
                }
                self.onExternalApplicationActivated?()
            }
        }
    }

    isolated deinit {
        if let workspaceActivationObserver {
            workspaceNotificationCenter.removeObserver(workspaceActivationObserver)
        }
    }

    var isVisible: Bool {
        panelIfCreated?.isVisible == true
    }

    func show() -> Bool {
        guard let panel = QLPreviewPanel.shared() else {
            return false
        }
        observe(panel)
        focusHandoffState = .openingQuickLook
        // Quick Look is an ordinary key window, and the palette is a
        // non-activating panel in an accessory app — so Bopop is usually NOT
        // the frontmost application when ⌘Y is pressed. Ordering the preview
        // panel in without activating first makes it take key and give it
        // straight back, which reads as "it opened and closed immediately".
        // Measured: didBecomeKey followed at once by didResignKey, with the
        // user's terminal still frontmost.
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        return true
    }

    func hide() {
        guard let panel = panelIfCreated, panel.isVisible else {
            return
        }
        focusHandoffState = .resolvingQuickLookResign
        panel.orderOut(nil)
    }

    func reload() {
        panelIfCreated?.reloadData()
    }

    func finishResignResolution() {
        focusHandoffState = .stable
    }

    private var panelIfCreated: QLPreviewPanel? {
        guard QLPreviewPanel.sharedPreviewPanelExists() else {
            return nil
        }
        return QLPreviewPanel.shared()
    }

    private func observe(_ panel: QLPreviewPanel) {
        guard didBecomeKeyObserver == nil else {
            return
        }
        didBecomeKeyObserver = NotificationToken(
            name: NSWindow.didBecomeKeyNotification,
            object: panel
        ) { [weak self] in
            self?.focusHandoffState = .stable
        }
        didResignKeyObserver = NotificationToken(
            name: NSWindow.didResignKeyNotification,
            object: panel
        ) { [weak self] in
            guard let self else { return }
            focusHandoffState = .resolvingQuickLookResign
            onResign?()
        }
    }
}
