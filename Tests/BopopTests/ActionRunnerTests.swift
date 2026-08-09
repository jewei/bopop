import Foundation
import Testing
@testable import Bopop
@testable import BopopKit

/// `.openURL` payloads reach NSWorkspace from user-authored custom-search
/// templates, so this allowlist is the app's guard against a template that
/// tries to launch something other than a web page.
@Test func allowedURLAcceptsOnlyWebAndDictionarySchemes() {
    #expect(ActionRunner.allowedURL(from: "https://example.com/x?q=1") != nil)
    #expect(ActionRunner.allowedURL(from: "http://example.com") != nil)
    #expect(ActionRunner.allowedURL(from: "dict://word") != nil)
}

@Test func allowedURLRejectsEverythingElse() {
    for rejected in [
        "file:///etc/passwd",
        "ftp://example.com",
        "javascript:alert(1)",
        "x-apple-systempreferences://",
        "mailto:someone@example.com",
        "",
        "not a url at all"
    ] {
        #expect(ActionRunner.allowedURL(from: rejected) == nil, "\(rejected) should be rejected")
    }
}

/// URL(string:) preserves the case it was given, so an uppercase scheme used
/// to fall through the guard and silently do nothing.
@Test func allowedURLIsCaseInsensitiveOnScheme() {
    #expect(ActionRunner.allowedURL(from: "HTTPS://example.com") != nil)
    #expect(ActionRunner.allowedURL(from: "FILE:///etc/passwd") == nil)
}

// MARK: - Typed failures

@MainActor
private func makeRunner(
    effects: ActionEffects,
    onFailure: @escaping (ActionFailure) -> Void
) throws -> (ActionRunner, URL) {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("bopop-runner-\(UUID().uuidString)", isDirectory: true)
    let storage = Storage(baseDirectory: root)
    try storage.ensureDirectories()
    let runner = ActionRunner(
        storage: storage,
        clipboardStore: ClipboardStore(storage: storage),
        visibilityStore: VisibilityStore(storage: storage),
        scriptFeedback: ScriptFeedback(storage: storage),
        effects: effects
    )
    runner.onFailure = onFailure
    return (runner, root)
}

@MainActor
private func effects(
    fileExists: @escaping (String) -> Bool = { _ in true },
    openFile: @escaping (URL) -> Bool = { _ in true },
    openURL: @escaping (URL) -> Bool = { _ in true },
    terminate: @escaping (String) -> Int = { _ in 1 },
    runProcess: @escaping (String, [String]) -> Result<Void, Error> = { _, _ in .success(()) },
    sendLoginwindowEvent: @escaping (String) -> Bool = { _ in true }
) -> ActionEffects {
    var value = ActionEffects.live
    value.fileExists = fileExists
    value.openFile = openFile
    value.openURL = openURL
    value.terminateApplications = terminate
    value.runProcess = runProcess
    value.sendLoginwindowEvent = sendLoginwindowEvent
    value.revealFile = { _ in }
    value.copyText = { _ in }
    value.openApplication = { _ in .success(()) }
    return value
}

/// An app moved or deleted since the last catalog scan used to do nothing at
/// all: `openApplication`'s completion error was discarded.
@MainActor
@Test func openingAMissingApplicationReportsIt() throws {
    var failures: [ActionFailure] = []
    let (runner, root) = try makeRunner(
        effects: effects(fileExists: { _ in false }),
        onFailure: { failures.append($0) }
    )
    defer { try? FileManager.default.removeItem(at: root) }

    runner.perform(SearchResult(
        id: "app:x", providerID: .apps, title: "Gone",
        action: .openApp("/Applications/Gone.app"), sortHint: 0
    ))

    #expect(failures == [.applicationMissing(path: "/Applications/Gone.app")])
}

@MainActor
@Test func openingAFileNothingHandlesReportsIt() throws {
    var failures: [ActionFailure] = []
    let (runner, root) = try makeRunner(
        effects: effects(openFile: { _ in false }),
        onFailure: { failures.append($0) }
    )
    defer { try? FileManager.default.removeItem(at: root) }

    runner.perform(SearchResult(
        id: "file:x", providerID: .files, title: "Doc",
        action: .openFile("/tmp/doc.weird"), sortHint: 0
    ))

    #expect(failures == [.fileDidNotOpen(path: "/tmp/doc.weird")])
}

/// A template that resolves to a non-web scheme is refused by `allowedURL`.
/// That refusal used to be a bare `return`.
@MainActor
@Test func rejectedURLSchemeReportsItInsteadOfDoingNothing() throws {
    var failures: [ActionFailure] = []
    let (runner, root) = try makeRunner(
        effects: effects(),
        onFailure: { failures.append($0) }
    )
    defer { try? FileManager.default.removeItem(at: root) }

    runner.perform(SearchResult(
        id: "web:x", providerID: .webSearch, title: "Search",
        action: .openURL("file:///etc/passwd"), sortHint: 0
    ))

    #expect(failures == [.urlRejected("file:///etc/passwd")])
}

@MainActor
@Test func quittingAnApplicationThatIsGoneReportsIt() throws {
    var failures: [ActionFailure] = []
    let (runner, root) = try makeRunner(
        effects: effects(terminate: { _ in 0 }),
        onFailure: { failures.append($0) }
    )
    defer { try? FileManager.default.removeItem(at: root) }

    runner.performQuit(SearchResult(
        id: "app:x", providerID: .apps, title: "Ghost",
        action: .openApp("/Applications/Ghost.app"),
        secondaryActions: [.quitApp("com.example.ghost")],
        sortHint: 0
    ))

    #expect(failures == [.applicationNotRunning(bundleID: "com.example.ghost")])
}

/// A system command that cannot launch used to be `try?`, so locking the screen
/// simply did nothing.
@MainActor
@Test func aSystemCommandThatCannotLaunchReportsIt() throws {
    struct LaunchError: LocalizedError {
        var errorDescription: String? { "No such file" }
    }
    var failures: [ActionFailure] = []
    let (runner, root) = try makeRunner(
        effects: effects(runProcess: { _, _ in .failure(LaunchError()) }),
        onFailure: { failures.append($0) }
    )
    defer { try? FileManager.default.removeItem(at: root) }
    // Lock Screen: no Bopop-side confirmation, and a plain process launch.
    let command = SystemCommand.lockScreen

    runner.perform(SearchResult(
        id: "cmd:x", providerID: .system, title: command.title,
        action: .systemCommand(command), sortHint: 0
    ))

    #expect(failures == [.commandFailed(title: command.title, reason: "No such file")])
}

@MainActor
@Test func successfulActionsReportNothing() throws {
    var failures: [ActionFailure] = []
    let (runner, root) = try makeRunner(
        effects: effects(),
        onFailure: { failures.append($0) }
    )
    defer { try? FileManager.default.removeItem(at: root) }

    runner.perform(SearchResult(
        id: "file:x", providerID: .files, title: "Doc",
        action: .openFile("/tmp/doc.txt"), sortHint: 0
    ))
    runner.perform(SearchResult(
        id: "web:x", providerID: .webSearch, title: "Search",
        action: .openURL("https://example.com"), sortHint: 0
    ))

    #expect(failures.isEmpty)
}
