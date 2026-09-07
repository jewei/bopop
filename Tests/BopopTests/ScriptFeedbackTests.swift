import Foundation
import Testing
@testable import Bopop
@testable import BopopKit

@MainActor
@Test(arguments: [Int32(0), Int32(7)])
func scriptFeedbackReportsFinalLineAndLogsCapturedOutput(exitCode: Int32) throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("bopop-feedback-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let storage = Storage(baseDirectory: root)
    try storage.ensureDirectories()
    let feedback = ScriptFeedback(storage: storage)
    var message: String?
    var failure: Bool?
    feedback.present = { message = $0; failure = $1 }
    let result = ScriptRunResult(
        exitCode: exitCode,
        stdout: "starting\nall done\n \n",
        stderr: "progress\nfinal failure\n\t\n",
        launchFailure: nil
    )

    feedback.report(name: "fixture", result: result)

    #expect(message == (exitCode == 0 ? "fixture: all done" : "fixture exited 7: final failure"))
    #expect(failure == (exitCode != 0))
    let log = try String(contentsOf: storage.scriptsLogURL, encoding: .utf8)
    #expect(log.contains(result.stdout))
    #expect(log.contains(result.stderr))
}
