import BopopKit
import Foundation

@MainActor
final class ScriptFeedback {
    private let storage: Storage
    /// Wired to the message HUD by `AppDelegate`. This used to post a user
    /// notification, which meant asking for the Notifications permission the
    /// first time a script finished — and losing every result thereafter if the
    /// user said no. The full output still goes to `scripts.log` either way.
    var present: ((String, Bool) -> Void)?

    init(storage: Storage) {
        self.storage = storage
    }

    func report(name: String, result: ScriptRunResult) {
        storage.appendScriptLog(logEntry(name: name, result: result))
        let succeeded = result.launchFailure == nil && result.exitCode == 0
        present?(summary(name: name, result: result, succeeded: succeeded), !succeeded)
    }

    private func summary(
        name: String,
        result: ScriptRunResult,
        succeeded: Bool
    ) -> String {
        let output = succeeded ? result.stdout : result.stderr
        let excerpt = String(output.prefix(120))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if succeeded {
            return excerpt.isEmpty ? "\(name) finished." : "\(name): \(excerpt)"
        }
        let status = result.exitCode.map { "exited \($0)" } ?? "didn't start"
        return excerpt.isEmpty
            ? "\(name) \(status)."
            : "\(name) \(status): \(excerpt)"
    }

    private func logEntry(name: String, result: ScriptRunResult) -> String {
        let status = result.exitCode.map(String.init) ?? "launch-failed"
        var entry = "\(name) exit=\(status)"
        entry += " stdoutBytes=\(result.stdout.utf8.count)"
        entry += " stderrBytes=\(result.stderr.utf8.count)"
        append(result.stdout, label: "stdout", to: &entry)
        append(result.stderr, label: "stderr", to: &entry)
        return entry
    }

    private func append(_ output: String, label: String, to entry: inout String) {
        guard !output.isEmpty else {
            return
        }
        entry += "\n--- \(label) ---\n\(output)"
        if !output.hasSuffix("\n") {
            entry += "\n"
        }
        entry += "--- end \(label) ---"
    }

}
