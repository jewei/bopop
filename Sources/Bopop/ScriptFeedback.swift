import BopopKit
import Foundation
import UserNotifications

@MainActor
final class ScriptFeedback {
    private let storage: Storage
    private var requestedNotificationAuthorization = false

    init(storage: Storage) {
        self.storage = storage
    }

    func report(name: String, result: ScriptRunResult) {
        storage.appendScriptLog(logEntry(name: name, result: result))
        postNotification(name: name, result: result)
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

    private func postNotification(name: String, result: ScriptRunResult) {
        guard Bundle.main.bundleIdentifier != nil else {
            return
        }

        let succeeded = result.launchFailure == nil && result.exitCode == 0
        let content = UNMutableNotificationContent()
        content.title = succeeded ? "Script succeeded" : "Script failed"
        content.subtitle = name
        content.body = notificationBody(result: result, succeeded: succeeded)
        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        let notificationCenter = UNUserNotificationCenter.current()
        let shouldRequestAuthorization = !requestedNotificationAuthorization
        requestedNotificationAuthorization = true

        Task {
            if shouldRequestAuthorization {
                _ = try? await notificationCenter.requestAuthorization(options: [.alert])
            }
            try? await notificationCenter.add(request)
        }
    }

    private func notificationBody(
        result: ScriptRunResult,
        succeeded: Bool
    ) -> String {
        let status: String
        if let exitCode = result.exitCode {
            status = "Exit \(exitCode)"
        } else {
            status = "Launch failed"
        }
        let output = succeeded ? result.stdout : result.stderr
        let excerpt = String(output.prefix(120))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return excerpt.isEmpty ? status : "\(status): \(excerpt)"
    }
}
