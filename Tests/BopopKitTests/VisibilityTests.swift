import Foundation
import Testing
@testable import BopopKit

@MainActor
@Test
func visibilityStoreHidesShowsAndPersists() throws {
    let fixture = try makeTestStorage()
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    let store = VisibilityStore(storage: fixture.storage)

    #expect(store.hiddenIDs.isEmpty)
    #expect(!store.isHidden("app:com.example.helper"))

    store.hide("app:com.example.helper")
    store.hide("app:com.example.helper") // idempotent
    #expect(store.isHidden("app:com.example.helper"))
    #expect(store.hiddenIDs.count == 1)

    let reloaded = VisibilityStore(storage: fixture.storage)
    #expect(reloaded.isHidden("app:com.example.helper"))

    reloaded.show("app:com.example.helper")
    #expect(VisibilityStore(storage: fixture.storage).hiddenIDs.isEmpty)
}

/// Hidden apps are dropped before scoring, so they cost nothing downstream
/// and `sortHint` numbers only what's visible.
@MainActor
@Test
func appsProviderDropsHiddenResultsAndRenumbers() async throws {
    let catalog = AppCatalog(directories: [], extraApplicationPaths: [])
    await catalog.refreshNow()

    let provider = AppsProvider(
        catalog: catalog,
        frecencyFor: { _ in [:] },
        hiddenIDs: { ["app:/Applications/Hidden.app"] }
    )
    let results = try await provider.results(for: ParsedQuery(mode: .apps, term: "a"))
    #expect(!results.contains { $0.id == "app:/Applications/Hidden.app" })
}

/// Quit is only offered for apps that are actually running, and never carries
/// a keyboard chord — ⌘⏎ is already Reveal in Finder for those same rows.
@Test
func quitActionAppearsOnlyForRunningAppsAndHasNoShortcut() {
    let running = SearchResult(
        id: "app:com.example.editor", providerID: .apps, title: "Editor",
        action: .openApp("/Applications/Editor.app"),
        secondaryActions: [.revealFile("/Applications/Editor.app"), .quitApp("com.example.editor")],
        sortHint: 0)
    let idle = SearchResult(
        id: "app:com.example.other", providerID: .apps, title: "Other",
        action: .openApp("/Applications/Other.app"),
        secondaryActions: [.revealFile("/Applications/Other.app")],
        sortHint: 0)

    let runningItems = ResultActions.items(for: running)
    #expect(runningItems.contains { $0.kind == .quit })
    #expect(runningItems.first { $0.kind == .quit }?.shortcut == nil)
    #expect(runningItems.first { $0.kind == .reveal }?.shortcut == "⌘⏎")
    #expect(!ResultActions.items(for: idle).contains { $0.kind == .quit })
    #expect(ResultActions.verb(for: .quitApp("x")) == "quit")
}

/// A debug build gets its own Application Support directory; release keeps
/// the historical one, or every existing user loses their data.
@Test
func storageDirectoryIsolatesTheDevChannelOnly() {
    #expect(Storage.directoryName(forBundleIdentifier: "com.oneone.bopop") == "Bopop")
    #expect(Storage.directoryName(forBundleIdentifier: nil) == "Bopop")
    #expect(Storage.directoryName(forBundleIdentifier: "com.oneone.bopop.dev") == "Bopop Dev")
}
