import AppKit

/// Tracks which apps are running so the palette can offer to quit them.
///
/// `AppsProvider` lives in UI-framework-independent BopopKit and can't see
/// `NSRunningApplication` — so this sits in the app target and is injected as
/// a closure, the same shape as the other settings lookups in `AppDelegate`.
///
/// Kept as a snapshot updated by notifications rather than calling
/// `NSWorkspace.runningApplications` per query: that property allocates a
/// full array of `NSRunningApplication` objects, and the provider runs on
/// every keystroke.
@MainActor
final class RunningApplicationsMonitor {
    /// Never offered as quittable. Finder relaunches immediately, so quitting
    /// it is a no-op with a flicker; and quitting Bopop from Bopop already has
    /// a dedicated footer item that shuts down cleanly.
    private static let neverQuittable: Set<String> = [
        "com.apple.finder"
    ]

    private(set) var bundleIDs: Set<String> = []
    private var observers: [NSObjectProtocol] = []

    func start() {
        refresh()
        let center = NSWorkspace.shared.notificationCenter
        for name in [
            NSWorkspace.didLaunchApplicationNotification,
            NSWorkspace.didTerminateApplicationNotification
        ] {
            let observer = center.addObserver(
                forName: name,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.refresh()
                }
            }
            observers.append(observer)
        }
    }

    private func refresh() {
        let excluded = Self.neverQuittable.union([Bundle.main.bundleIdentifier].compactMap { $0 })
        bundleIDs = Set(
            NSWorkspace.shared.runningApplications.compactMap { application in
                guard application.activationPolicy == .regular,
                      let bundleID = application.bundleIdentifier,
                      !excluded.contains(bundleID) else {
                    return nil
                }
                return bundleID
            }
        )
    }

    /// These are block-based observers, so they outlive this object unless
    /// explicitly removed — and the callback would then fire into freed memory.
    isolated deinit {
        let center = NSWorkspace.shared.notificationCenter
        for observer in observers {
            center.removeObserver(observer)
        }
    }
}
