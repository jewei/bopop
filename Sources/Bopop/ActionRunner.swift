import AppKit
import BopopKit
import Carbon

@MainActor
final class ActionRunner {
    private let storage: Storage
    private let clipboardStore: ClipboardStore
    private let scriptFeedback: ScriptFeedback

    var onModeChange: ((Mode) -> Void)?
    var onExecuted: ((SearchResult) -> Void)?
    var hidePalette: (() -> Void)?
    var onDownloadTranslation: (() -> Void)?

    init(
        storage: Storage,
        clipboardStore: ClipboardStore,
        scriptFeedback: ScriptFeedback
    ) {
        self.storage = storage
        self.clipboardStore = clipboardStore
        self.scriptFeedback = scriptFeedback
    }

    func perform(_ result: SearchResult) {
        if case let .enterMode(mode) = result.action {
            onModeChange?(mode)
            return
        }

        hidePalette?()
        onExecuted?(result)
        execute(result.action)
    }

    /// Reveal routes through the runner like copy does — hide, then
    /// execute — without the full `perform` path (no usage recording, no
    /// `onExecuted` callback), since revealing isn't "activating" a result.
    func performReveal(_ path: String) {
        hidePalette?()
        execute(.revealFile(path))
    }

    func performCopy(_ result: SearchResult) {
        let secondaryCopy = result.secondaryActions.first { action in
            if case .copyText = action {
                return true
            }
            return false
        }
        let copyAction = secondaryCopy ?? result.action
        guard case .copyText = copyAction else {
            return
        }

        hidePalette?()
        execute(copyAction)
        onExecuted?(result)
    }

    private func execute(_ action: ResultAction) {
        switch action {
        case let .openApp(path):
            NSWorkspace.shared.openApplication(
                at: URL(fileURLWithPath: path),
                configuration: .init()
            )
        case let .openFile(path):
            NSWorkspace.shared.open(URL(fileURLWithPath: path))
        case let .copyText(text):
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
        case .clearClipboardHistory:
            clipboardStore.clear()
        case let .runScript(path):
            let name = URL(fileURLWithPath: path)
                .deletingPathExtension()
                .lastPathComponent
            // ponytail: no timeout — add a SIGTERM deadline if a hung script ever bothers anyone
            Task {
                let result = await ScriptRunner.run(
                    scriptAt: path,
                    workingDirectory: storage.scriptsDirectory
                )
                scriptFeedback.report(name: name, result: result)
            }
        case .enterMode:
            break
        case let .openURL(string):
            guard let url = URL(string: string),
                  url.scheme == "http" || url.scheme == "https" || url.scheme == "dict" else {
                return
            }
            NSWorkspace.shared.open(url)
        case .downloadTranslation:
            onDownloadTranslation?()
        case .systemCommand(let command):
            run(command.invocation)
        case let .revealFile(path):
            NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
        }
    }

    private func run(_ invocation: SystemCommandInvocation) {
        switch invocation {
        case .process(let executable, let arguments):
            let process = Process()
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = arguments
            try? process.run()
        case .loginwindowAppleEvent(let code):
            sendLoginwindowEvent(fourCharCode(code))
        case .finderScript(let source):
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            process.arguments = ["-e", source]
            try? process.run()
        }
    }

    private func fourCharCode(_ code: String) -> AEEventID {
        code.utf8.reduce(0) { ($0 << 8) + AEEventID($1) }
    }

    private func sendLoginwindowEvent(_ eventID: AEEventID) {
        var psn = ProcessSerialNumber(highLongOfPSN: 0, lowLongOfPSN: UInt32(kSystemProcess))
        var target = AEAddressDesc()
        guard AECreateDesc(typeProcessSerialNumber, &psn,
                           MemoryLayout.size(ofValue: psn), &target) == noErr else { return }
        defer { AEDisposeDesc(&target) }
        var event = AppleEvent()
        guard AECreateAppleEvent(kCoreEventClass, eventID, &target,
                                 AEReturnID(kAutoGenerateReturnID),
                                 AETransactionID(kAnyTransactionID), &event) == noErr else { return }
        defer { AEDisposeDesc(&event) }
        var reply = AppleEvent()
        AESendMessage(&event, &reply, AESendMode(kAENoReply), kAEDefaultTimeout)
    }
}
