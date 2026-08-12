import AppKit
import BopopKit

@MainActor
final class PasteboardWatcher {
    static let defaultDeniedSources: Set<String> = [
        "com.apple.Passwords",
        "com.apple.keychainaccess"
    ]
    // Narrowed from 600 s: the scrub exists for sensitive managers (Apple
    // Passwords clears ~90 s after a copy) — a bare clearContents from any
    // other app minutes later shouldn't delete unrelated history. True
    // source attribution is impossible (NSPasteboard doesn't identify the
    // clearer), so this window is the only lever available.
    static let upstreamClearScrubWindow: TimeInterval = 120

    private let store: ClipboardStore
    private let pasteboard: NSPasteboard
    private let interval: TimeInterval
    private let deniedSourceBundleIDs: Set<String>
    private let workspaceNotificationCenter: NotificationCenter
    private let frontmostBundleID: () -> String?
    private var lastChangeCount = 0
    private var timer: Timer?
    private var sessionObservers: [NotificationToken] = []
    private var isStarted = false
    private var isSessionActive = true

    init(
        store: ClipboardStore,
        pasteboard: NSPasteboard = .general,
        interval: TimeInterval = 0.5,
        deniedSourceBundleIDs: Set<String> = PasteboardWatcher.defaultDeniedSources,
        workspaceNotificationCenter: NotificationCenter = NSWorkspace.shared.notificationCenter,
        frontmostBundleID: @escaping () -> String? = {
            NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        }
    ) {
        self.store = store
        self.pasteboard = pasteboard
        self.interval = interval
        self.deniedSourceBundleIDs = deniedSourceBundleIDs
        self.workspaceNotificationCenter = workspaceNotificationCenter
        self.frontmostBundleID = frontmostBundleID
    }

    func start() {
        isStarted = true
        isSessionActive = true
        lastChangeCount = pasteboard.changeCount
        observeSessionChangesIfNeeded()
        startTimer()
    }

    func stop() {
        isStarted = false
        isSessionActive = false
        timer?.invalidate()
        timer = nil
        sessionObservers.removeAll()
    }

    private func startTimer() {
        timer?.invalidate()
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.pollPasteboard()
            }
        }
        timer.tolerance = 0.2
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func observeSessionChangesIfNeeded() {
        guard sessionObservers.isEmpty else {
            return
        }
        sessionObservers = [
            NotificationToken(
                center: workspaceNotificationCenter,
                name: NSWorkspace.sessionDidResignActiveNotification
            ) { [weak self] in
                self?.sessionDidResignActive()
            },
            NotificationToken(
                center: workspaceNotificationCenter,
                name: NSWorkspace.sessionDidBecomeActiveNotification
            ) { [weak self] in
                self?.sessionDidBecomeActive()
            }
        ]
    }

    /// Fast user switching: another login session owns the screen, so polling
    /// there is two wakeups a second spent on a pasteboard we must not read.
    private func sessionDidResignActive() {
        isSessionActive = false
        timer?.invalidate()
        timer = nil
    }

    /// Re-baseline BEFORE the first poll resumes. `changeCount` is global, so
    /// whatever the other user copied while we were away looks like a brand new
    /// change to us — capturing it would put their clipboard in our history.
    private func sessionDidBecomeActive() {
        guard isStarted else {
            return
        }
        lastChangeCount = pasteboard.changeCount
        isSessionActive = true
        startTimer()
    }

    /// Internal rather than private so tests can drive one poll directly
    /// instead of waiting on the timer — the capture/clear dispatch below is
    /// the part worth pinning down, not the scheduling around it.
    func pollPasteboard() {
        guard isSessionActive else {
            return
        }
        let changeCount = pasteboard.changeCount
        guard changeCount != lastChangeCount else {
            return
        }
        lastChangeCount = changeCount

        let types = pasteboard.types ?? []
        if ClipboardCapturePolicy.isUpstreamClear(types: types.map(\.rawValue)) {
            // A bare clearContents (Apple Passwords fires one ~90 s after a
            // copy) means the source considered the content sensitive — forget
            // our newest capture too.
            store.forgetCaptures(within: Self.upstreamClearScrubWindow)
            return
        }
        // The secrecy-marker check lives entirely in ClipboardCapturePolicy —
        // this used to repeat two of the markers here, which meant the set of
        // "never record this" types had two homes and only one of them was
        // consulted for the third.
        //
        // Heuristic: the frontmost app within one 0.5 s poll of a copy is almost
        // always the copier. This catches Apple Passwords, which sets no pasteboard
        // marker at all (verified on macOS 15.7).
        guard ClipboardCapturePolicy.shouldCapture(
            types: types.map(\.rawValue),
            frontmostBundleID: frontmostBundleID(),
            denied: deniedSourceBundleIDs
        ) else {
            return
        }
        guard let text = pasteboard.string(forType: .string) else {
            return
        }

        // Re-copying a history entry is deduplicated or promoted by the store.
        store.add(text)
    }
}
