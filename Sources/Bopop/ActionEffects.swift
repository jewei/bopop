import AppKit

/// The platform side effects `ActionRunner` performs, behind one injectable
/// value. Production wires these to `NSWorkspace`/`Process`; tests substitute
/// closures and assert on what the runner decided, without opening anything.
///
/// Coarse on purpose: one closure per effect the runner actually performs, not
/// a general-purpose wrapper around AppKit.
@MainActor
struct ActionEffects {
    var openApplication: (URL) async -> Result<Void, Error>
    var openFile: (URL) -> Bool
    var openURL: (URL) -> Bool
    var revealFile: (URL) -> Void
    var fileExists: (String) -> Bool
    /// Bundle identifiers of running apps matching the given identifier, and a
    /// request to terminate them. Returns how many were asked to quit.
    var terminateApplications: (String) -> Int
    var runProcess: (String, [String]) -> Result<Void, Error>
    var sendLoginwindowEvent: (String) -> Bool
    var copyText: (String) -> Void

    static let live = ActionEffects(
        openApplication: { url in
            await withCheckedContinuation { continuation in
                NSWorkspace.shared.openApplication(
                    at: url,
                    configuration: NSWorkspace.OpenConfiguration()
                ) { _, error in
                    if let error {
                        continuation.resume(returning: .failure(error))
                    } else {
                        continuation.resume(returning: .success(()))
                    }
                }
            }
        },
        openFile: { NSWorkspace.shared.open($0) },
        openURL: { NSWorkspace.shared.open($0) },
        revealFile: { NSWorkspace.shared.activateFileViewerSelecting([$0]) },
        fileExists: { FileManager.default.fileExists(atPath: $0) },
        terminateApplications: { bundleID in
            let running = NSRunningApplication.runningApplications(
                withBundleIdentifier: bundleID
            )
            for application in running {
                // `terminate()` rather than `forceTerminate()`: the app gets to
                // run its own quit path, prompt to save, or refuse.
                application.terminate()
            }
            return running.count
        },
        runProcess: { executable, arguments in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = arguments
            do {
                try process.run()
                return .success(())
            } catch {
                return .failure(error)
            }
        },
        sendLoginwindowEvent: { code in
            LoginWindowEvent.send(code)
        },
        copyText: { text in
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
        }
    )
}

/// Why an action did not do what the row promised. Every case carries enough
/// to tell the user something they can act on — these used to be `try?` and
/// ignored return values, so a moved app or a denied Automation prompt looked
/// exactly like success.
enum ActionFailure: Equatable {
    case applicationMissing(path: String)
    case applicationDidNotOpen(path: String, reason: String)
    case fileMissing(path: String)
    case fileDidNotOpen(path: String)
    case urlRejected(String)
    case urlDidNotOpen(String)
    case applicationNotRunning(bundleID: String)
    case commandFailed(title: String, reason: String)

    var message: String {
        switch self {
        case .applicationMissing(let path):
            "\(Self.name(of: path)) is no longer at that location."
        case .applicationDidNotOpen(let path, let reason):
            "Couldn't open \(Self.name(of: path)): \(reason)"
        case .fileMissing(let path):
            "\(Self.name(of: path)) is no longer at that location."
        case .fileDidNotOpen(let path):
            "Nothing is set up to open \(Self.name(of: path))."
        case .urlRejected(let string):
            "That link isn't a web address: \(string)"
        case .urlDidNotOpen(let string):
            "Couldn't open \(string)"
        case .applicationNotRunning(let bundleID):
            "\(bundleID) isn't running any more."
        case .commandFailed(let title, let reason):
            "\(title) failed: \(reason)"
        }
    }

    private static func name(of path: String) -> String {
        (path as NSString).lastPathComponent
    }
}

/// The Apple-event path to loginwindow, extracted so `ActionEffects` can hold
/// it as a plain closure and tests can replace it.
enum LoginWindowEvent {
    static func send(_ code: String) -> Bool {
        let eventID = code.utf8.reduce(0) { ($0 << 8) + AEEventID($1) }
        var psn = ProcessSerialNumber(
            highLongOfPSN: 0,
            lowLongOfPSN: UInt32(kSystemProcess)
        )
        var target = AEAddressDesc()
        guard AECreateDesc(
            typeProcessSerialNumber,
            &psn,
            MemoryLayout.size(ofValue: psn),
            &target
        ) == noErr else {
            return false
        }
        defer { AEDisposeDesc(&target) }
        var event = AppleEvent()
        guard AECreateAppleEvent(
            kCoreEventClass,
            eventID,
            &target,
            AEReturnID(kAutoGenerateReturnID),
            AETransactionID(kAnyTransactionID),
            &event
        ) == noErr else {
            return false
        }
        defer { AEDisposeDesc(&event) }
        var reply = AppleEvent()
        return AESendMessage(
            &event,
            &reply,
            AESendMode(kAENoReply),
            kAEDefaultTimeout
        ) == noErr
    }
}
