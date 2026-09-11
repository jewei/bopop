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
    // Stubbed like every other effect: the live one writes to the user's real
    // pasteboard, and a test suite has no business clobbering it.
    value.copySecret = { _ in }
    value.openApplication = { _ in .success(()) }
    return value
}

@MainActor
@Test func disabledResultDoesNotDismissOrRecordExecution() throws {
    var failures: [ActionFailure] = []
    let (runner, root) = try makeRunner(
        effects: effects(),
        onFailure: { failures.append($0) }
    )
    defer { try? FileManager.default.removeItem(at: root) }
    var didHide = false
    var didExecute = false
    runner.hidePalette = { didHide = true }
    runner.onExecuted = { _ in didExecute = true }

    runner.perform(SearchResult(
        id: "info", providerID: .currency, title: "Unavailable",
        action: .disabled, sortHint: 0
    ))

    #expect(!didHide)
    #expect(!didExecute)
    #expect(failures.isEmpty)
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

/// A generated password must never take the plain-copy path: that write
/// reaches the pasteboard unmarked, and Bopop's own watcher records it half a
/// second later.
@MainActor
@Test func copyingAGeneratedPasswordTakesTheMarkedPath() throws {
    var plain: [String] = []
    var secret: [String] = []
    var value = effects()
    value.copyText = { plain.append($0) }
    value.copySecret = { secret.append($0) }
    let (runner, root) = try makeRunner(effects: value, onFailure: { _ in })
    defer { try? FileManager.default.removeItem(at: root) }
    runner.hidePalette = {}

    runner.perform(SearchResult(
        id: "password:strong", providerID: .password, title: "aB3!xQ",
        action: .copySecret("aB3!xQ"), sortHint: 0
    ))

    #expect(secret == ["aB3!xQ"])
    #expect(plain.isEmpty)
}

/// ⌘C reaches the same marked path. `performCopy` used to pattern-match
/// `.copyText`, while `ResultActions.hasCopyAction` — which decides whether
/// ⌘C is offered — asks for the `.copy` role; a secret copy satisfied the
/// second and not the first, so the key did nothing at all.
@MainActor
@Test func commandCCopiesASecretRatherThanSilentlyDoingNothing() throws {
    var secret: [String] = []
    var value = effects()
    value.copySecret = { secret.append($0) }
    let (runner, root) = try makeRunner(effects: value, onFailure: { _ in })
    defer { try? FileManager.default.removeItem(at: root) }
    runner.hidePalette = {}

    let result = SearchResult(
        id: "password:pin", providerID: .password, title: "402913",
        action: .copySecret("402913"), sortHint: 0
    )
    #expect(ResultActions.hasCopyAction(result))
    runner.performCopy(result)

    #expect(secret == ["402913"])
}
