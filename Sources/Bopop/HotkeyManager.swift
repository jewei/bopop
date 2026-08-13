import BopopKit
import Carbon.HIToolbox
import os

private nonisolated func handleHotkeyEvent(
    _ nextHandler: EventHandlerCallRef?,
    _ event: EventRef?,
    _ userData: UnsafeMutableRawPointer?
) -> OSStatus {
    guard let userData else {
        return OSStatus(eventNotHandledErr)
    }

    let manager = Unmanaged<HotkeyManager>.fromOpaque(userData).takeUnretainedValue()
    MainActor.assumeIsolated {
        manager.onHotkey?()
    }
    return noErr
}

@MainActor
final class HotkeyManager {
    var onHotkey: (() -> Void)?

    private let logger = Logger(subsystem: "com.oneone.bopop", category: "hotkey")
    private var hotkeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?
    private var attemptedEventHandlerInstallation = false

    /// Whether Bopop's last local Carbon registration succeeded. Carbon does
    /// not establish exclusivity against registrations in other processes.
    private(set) var isRegistered = false

    /// Returns Carbon's local registration outcome. This reports Bopop's own
    /// handler/registration failures; it does not establish exclusivity across
    /// processes, so callers must not label it as another-app conflict.
    @discardableResult
    func register(_ config: HotkeyConfig) -> HotkeyRegistrationOutcome {
        unregister()
        let handlerStatus = installEventHandlerIfNeeded()
        guard handlerStatus == noErr else {
            isRegistered = false
            return .eventHandlerFailed(handlerStatus)
        }

        var ref: EventHotKeyRef?
        let identifier = EventHotKeyID(signature: OSType(0x42504F50), id: 1)
        let status = RegisterEventHotKey(
            config.keyCode,
            config.carbonModifiers,
            identifier,
            GetEventDispatcherTarget(),
            0,
            &ref
        )

        guard status == noErr else {
            logger.error("Could not register global hotkey; Carbon status: \(status)")
            isRegistered = false
            return .registrationFailed(status)
        }
        hotkeyRef = ref
        isRegistered = true
        return .registered
    }

    func unregister() {
        isRegistered = false
        guard let hotkeyRef else {
            return
        }

        _ = UnregisterEventHotKey(hotkeyRef)
        self.hotkeyRef = nil
    }

    /// The Carbon handler holds `self` as an UNRETAINED opaque pointer and
    /// `handleHotkeyEvent` resurrects it with `takeUnretainedValue()`, so
    /// leaving it installed past this object's lifetime turns the next hotkey
    /// press into a use-after-free. Today AppDelegate owns the only instance
    /// for the whole process, but that invariant was implicit and unenforced.
    /// `isolated` so it can touch the two Carbon refs, which are
    /// non-Sendable OpaquePointers on a MainActor-isolated class.
    isolated deinit {
        if let hotkeyRef {
            _ = UnregisterEventHotKey(hotkeyRef)
        }
        if let eventHandlerRef {
            _ = RemoveEventHandler(eventHandlerRef)
        }
    }

    private func installEventHandlerIfNeeded() -> OSStatus {
        // Only latch `attemptedEventHandlerInstallation` on SUCCESS. If we
        // latched it unconditionally (as before), one transient
        // InstallEventHandler failure (e.g. an app launched before the
        // window server is fully up) would permanently disable the hotkey
        // for the rest of the process's lifetime — every later register()
        // call would short-circuit here and never retry. Leaving the flag
        // false on failure means the next register() (e.g. the user
        // reopening Settings and re-saving their hotkey) gets a fresh
        // attempt, while a successful install is still cached rather than
        // redone on every register().
        if attemptedEventHandlerInstallation {
            return eventHandlerRef == nil ? OSStatus(eventInternalErr) : noErr
        }

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let status = InstallEventHandler(
            GetEventDispatcherTarget(),
            handleHotkeyEvent,
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandlerRef
        )

        guard status == noErr else {
            logger.error("Could not install hotkey event handler; Carbon status: \(status)")
            return status
        }
        attemptedEventHandlerInstallation = true
        return noErr
    }
}

/// The local result of asking Carbon to install Bopop's handler and register a
/// shortcut. This is deliberately not called a "conflict" result:
/// `RegisterEventHotKey` does not report another process holding the same
/// combination, so a failure here is an internal registration failure whose
/// status should be surfaced without guessing at its cause.
enum HotkeyRegistrationOutcome: Equatable {
    case registered
    case eventHandlerFailed(OSStatus)
    case registrationFailed(OSStatus)

    var isRegistered: Bool { self == .registered }

    var failureMessage: String? {
        switch self {
        case .registered:
            nil
        case let .eventHandlerFailed(status):
            "Bopop couldn't install its shortcut handler (Carbon status \(status))."
        case let .registrationFailed(status):
            "Bopop couldn't register this shortcut (Carbon status \(status))."
        }
    }
}

@MainActor
protocol HotkeyRegistering: AnyObject {
    @discardableResult
    func register(_ config: HotkeyConfig) -> HotkeyRegistrationOutcome
    func unregister()
}

extension HotkeyManager: HotkeyRegistering {}
