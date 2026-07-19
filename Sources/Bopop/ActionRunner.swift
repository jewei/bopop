import AppKit
import BopopKit

@MainActor
final class ActionRunner {
    private let storage: Storage
    private let clipboardStore: ClipboardStore
    private let scriptFeedback: ScriptFeedback

    var onModeChange: ((Mode) -> Void)?
    var onExecuted: ((SearchResult) -> Void)?
    var hidePalette: (() -> Void)?

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
                  url.scheme == "http" || url.scheme == "https" else {
                return
            }
            NSWorkspace.shared.open(url)
        }
    }
}
