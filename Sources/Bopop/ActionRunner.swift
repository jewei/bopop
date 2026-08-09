import AppKit
import BopopKit
import Carbon

@MainActor
final class ActionRunner {
    private let storage: Storage
    private let clipboardStore: ClipboardStore
    private let visibilityStore: VisibilityStore
    private let scriptFeedback: ScriptFeedback
    private let effects: ActionEffects

    var onModeChange: ((Mode) -> Void)?
    var onExecuted: ((SearchResult) -> Void)?
    var hidePalette: (() -> Void)?
    var onDownloadTranslation: (() -> Void)?
    /// Fired after a mutation that must keep the palette open and re-query.
    var onStayOpenRefresh: (() -> Void)?
    /// Fired when an action could not do what its row promised. Wired to the
    /// message HUD in `AppDelegate`; the palette is already hidden by then, so
    /// there is nowhere else for the user to learn this.
    var onFailure: ((ActionFailure) -> Void)?

    init(
        storage: Storage,
        clipboardStore: ClipboardStore,
        visibilityStore: VisibilityStore,
        scriptFeedback: ScriptFeedback,
        effects: ActionEffects = .live
    ) {
        self.storage = storage
        self.clipboardStore = clipboardStore
        self.visibilityStore = visibilityStore
        self.scriptFeedback = scriptFeedback
        self.effects = effects
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

    /// Quitting closes the palette like any other activation — the result the
    /// user acted on is about to stop being runnable, so leaving the list up
    /// showing a stale "running" row would be worse than dismissing.
    func performQuit(_ result: SearchResult) {
        guard let action = ResultActions.quitAction(in: result) else {
            return
        }
        hidePalette?()
        execute(action)
    }

    /// Hiding keeps the palette open and re-queries, like pin — the row the
    /// user just hid should disappear from under them immediately.
    func performHide(_ result: SearchResult) {
        guard let action = ResultActions.hideAction(in: result) else {
            return
        }
        execute(action)
        onStayOpenRefresh?()
    }

    /// Pin/unpin keeps the palette open and refreshes the result list.
    func performPin(_ result: SearchResult) {
        guard let action = ResultActions.pinAction(in: result) else {
            return
        }
        execute(action)
        onStayOpenRefresh?()
    }

    /// The only schemes ever handed to NSWorkspace. `.openURL` payloads come
    /// from user-authored custom-search templates among other places, so this
    /// allowlist is what stops one from launching `file://` or an arbitrary
    /// app scheme. Pure and static so it can be tested without side effects.
    nonisolated static func allowedURL(from string: String) -> URL? {
        guard let url = URL(string: string),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" || scheme == "dict" else {
            return nil
        }
        return url
    }

    /// Every branch that can fail now reports why. The app-open and file-open
    /// paths in particular used to discard a completion error and a Bool: an
    /// app moved since the last catalog scan just did nothing at all.
    private func execute(_ action: ResultAction) {
        switch action {
        case let .openApp(path):
            guard effects.fileExists(path) else {
                onFailure?(.applicationMissing(path: path))
                return
            }
            Task { [effects, onFailure] in
                if case let .failure(error) = await effects.openApplication(
                    URL(fileURLWithPath: path)
                ) {
                    onFailure?(.applicationDidNotOpen(
                        path: path,
                        reason: error.localizedDescription
                    ))
                }
            }
        case let .openFile(path):
            guard effects.fileExists(path) else {
                onFailure?(.fileMissing(path: path))
                return
            }
            if !effects.openFile(URL(fileURLWithPath: path)) {
                onFailure?(.fileDidNotOpen(path: path))
            }
        case let .copyText(text):
            effects.copyText(text)
        case .clearClipboardHistory:
            clipboardStore.clear()
        case let .pinClipboard(id):
            clipboardStore.pin(id: id)
        case let .unpinClipboard(id):
            clipboardStore.unpin(id: id)
        case let .hideResult(id):
            visibilityStore.hide(id)
        case let .quitApp(bundleID):
            if effects.terminateApplications(bundleID) == 0 {
                onFailure?(.applicationNotRunning(bundleID: bundleID))
            }
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
            guard let url = Self.allowedURL(from: string) else {
                onFailure?(.urlRejected(string))
                return
            }
            if !effects.openURL(url) {
                onFailure?(.urlDidNotOpen(string))
            }
        case .downloadTranslation:
            onDownloadTranslation?()
        case .systemCommand(let command):
            guard confirmed(command) else {
                return
            }
            run(command)
        case let .revealFile(path):
            guard effects.fileExists(path) else {
                onFailure?(.fileMissing(path: path))
                return
            }
            effects.revealFile(URL(fileURLWithPath: path))
        }
    }

    /// True when the command needs no confirmation, or the user gave it.
    /// The palette is already hidden by the time `execute` runs, so this
    /// alert stands alone — and an accessory app has to activate itself for
    /// a modal to come to the front (same as `SpotlightConflict`).
    private func confirmed(_ command: SystemCommand) -> Bool {
        guard let confirmation = command.confirmation else {
            return true
        }
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = confirmation.message
        alert.informativeText = confirmation.informative
        alert.addButton(withTitle: confirmation.confirmTitle)
        alert.addButton(withTitle: "Cancel")
        NSApp.activate(ignoringOtherApps: true)
        return alert.runModal() == .alertFirstButtonReturn
    }

    /// A failed launch used to be `try?`: locking the screen or emptying the
    /// Trash simply did nothing, with no way to tell that from success.
    private func run(_ command: SystemCommand) {
        switch command.invocation {
        case .process(let executable, let arguments):
            if case let .failure(error) = effects.runProcess(executable, arguments) {
                onFailure?(.commandFailed(
                    title: command.title,
                    reason: error.localizedDescription
                ))
            }
        case .loginwindowAppleEvent(let code):
            if !effects.sendLoginwindowEvent(code) {
                onFailure?(.commandFailed(
                    title: command.title,
                    reason: "macOS refused the request."
                ))
            }
        case .finderScript(let source):
            // Automation permission is the usual reason this fails, and it is
            // denied silently — osascript exits nonzero long after `run()`
            // returns, so a launch success is all this can check.
            if case let .failure(error) = effects.runProcess(
                "/usr/bin/osascript",
                ["-e", source]
            ) {
                onFailure?(.commandFailed(
                    title: command.title,
                    reason: error.localizedDescription
                ))
            }
        }
    }
}
