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

final class HotkeyManager {
    var onHotkey: (() -> Void)?

    private let logger = Logger(subsystem: "com.oneone.bopop", category: "hotkey")
    private var hotkeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?
    private var attemptedEventHandlerInstallation = false

    func register(_ config: HotkeyConfig) {
        unregister()
        guard installEventHandlerIfNeeded() else {
            return
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
            return
        }
        hotkeyRef = ref
    }

    func unregister() {
        guard let hotkeyRef else {
            return
        }

        _ = UnregisterEventHotKey(hotkeyRef)
        self.hotkeyRef = nil
    }

    private func installEventHandlerIfNeeded() -> Bool {
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
            return eventHandlerRef != nil
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
            return false
        }
        attemptedEventHandlerInstallation = true
        return true
    }
}
