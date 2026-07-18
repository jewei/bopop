import AppKit
import BopopKit
import os

@MainActor
final class ActionRunner {
    var onModeChange: ((Mode) -> Void)?
    var onExecuted: ((SearchResult) -> Void)?
    var hidePalette: (() -> Void)?

    func perform(_ result: SearchResult) {
        if case let .enterMode(mode) = result.action {
            onModeChange?(mode)
            return
        }

        hidePalette?()
        execute(result.action)
        onExecuted?(result)
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
        case let .runScript(path):
            Self.logger.info(
                "Script execution lands in step 8: \(path, privacy: .private)"
            )
        case .enterMode:
            break
        }
    }

    private static let logger = Logger(
        subsystem: "com.oneone.bopop",
        category: "actions"
    )
}
