import AppKit
import BopopKit

@MainActor
final class PasteboardWatcher {
    static let defaultDeniedSources: Set<String> = [
        "com.apple.Passwords",
        "com.apple.keychainaccess"
    ]
    static let upstreamClearScrubWindow: TimeInterval = 600

    private static let concealedType = NSPasteboard.PasteboardType(
        "org.nspasteboard.ConcealedType"
    )
    private static let transientType = NSPasteboard.PasteboardType(
        "org.nspasteboard.TransientType"
    )

    private let store: ClipboardStore
    private let pasteboard: NSPasteboard
    private let interval: TimeInterval
    private let deniedSourceBundleIDs: Set<String>
    private let frontmostBundleID: () -> String?
    private var lastChangeCount = 0
    private var timer: Timer?

    init(
        store: ClipboardStore,
        pasteboard: NSPasteboard = .general,
        interval: TimeInterval = 0.5,
        deniedSourceBundleIDs: Set<String> = PasteboardWatcher.defaultDeniedSources,
        frontmostBundleID: @escaping () -> String? = {
            NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        }
    ) {
        self.store = store
        self.pasteboard = pasteboard
        self.interval = interval
        self.deniedSourceBundleIDs = deniedSourceBundleIDs
        self.frontmostBundleID = frontmostBundleID
    }

    func start() {
        lastChangeCount = pasteboard.changeCount
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

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func pollPasteboard() {
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
            store.forgetNewest(ifCapturedWithin: Self.upstreamClearScrubWindow)
            return
        }
        guard !types.contains(Self.concealedType),
              !types.contains(Self.transientType) else {
            return
        }
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
