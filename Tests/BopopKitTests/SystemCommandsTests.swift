import Foundation
import Testing
@testable import BopopKit

@Test func systemCommandCatalogCoversEveryCommand() {
    #expect(SystemCommand.allCases.count == 8)
    for command in SystemCommand.allCases {
        #expect(!command.title.isEmpty)
        #expect(!command.keywords.isEmpty)
        #expect(!command.symbolName.isEmpty)
    }
}

@Test func systemCommandInvocationsAreConfirmedOrSafe() {
    // Log out / restart / shut down must use the dialog-showing loginwindow
    // events so macOS itself confirms; nothing here bypasses that.
    #expect(SystemCommand.logOut.invocation == .loginwindowAppleEvent(code: "logo"))
    #expect(SystemCommand.restart.invocation == .loginwindowAppleEvent(code: "rrst"))
    #expect(SystemCommand.shutDown.invocation == .loginwindowAppleEvent(code: "rsdn"))
    #expect(SystemCommand.sleep.invocation
        == .process(executable: "/usr/bin/pmset", arguments: ["sleepnow"]))
    #expect(SystemCommand.lockScreen.invocation == .process(
        executable: "/System/Library/PrivateFrameworks/login.framework/Versions/Current/Resources/CGSession",
        arguments: ["-suspend"]))
    #expect(SystemCommand.screenSaver.invocation
        == .process(executable: "/usr/bin/open", arguments: ["-b", "com.apple.ScreenSaver.Engine"]))
    if case .finderScript(let source) = SystemCommand.emptyTrash.invocation {
        #expect(source.contains("empty trash"))
    } else { Issue.record("emptyTrash must be a Finder script") }
    if case .finderScript(let source) = SystemCommand.ejectAll.invocation {
        #expect(source.contains("eject"))
    } else { Issue.record("ejectAll must be a Finder script") }
}

@MainActor
@Test func systemCommandsProviderMatchesInGeneralModeOnly() async throws {
    let provider = SystemCommandsProvider()
    let empty = try await provider.results(for: ParsedQuery(mode: .general, term: ""))
    #expect(empty.isEmpty)
    let wrongMode = try await provider.results(for: ParsedQuery(mode: .clipboard, term: "lock"))
    #expect(wrongMode.isEmpty)

    let results = try await provider.results(for: ParsedQuery(mode: .general, term: "lock"))
    let lock = try #require(results.first { $0.id == "system:lockScreen" })
    #expect(lock.action == .systemCommand(.lockScreen))
    #expect(lock.badge == "System")
    #expect(lock.providerID == .system)
    // Provider returns the full catalog on a non-empty term; Ranker filters non-matches.
    #expect(results.count == SystemCommand.allCases.count)
}

@Test func systemProviderHasRankerWeight() {
    #expect(Ranker.defaultWeights[.system] == 55)
}
