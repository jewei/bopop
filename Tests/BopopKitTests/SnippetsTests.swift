import Foundation
import Testing
@testable import BopopKit

@MainActor
@Test func snippetStorePersistsSortedByName() throws {
    let fixture = try makeTestStorage()
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    let store = SnippetStore(storage: fixture.storage)
    try store.add(Snippet(id: UUID(), name: "Zeta", keyword: nil, content: "z"))
    try store.add(Snippet(id: UUID(), name: "Alpha", keyword: "em", content: "a@b.c"))
    #expect(store.snippets.map(\.name) == ["Alpha", "Zeta"])

    let reloaded = SnippetStore(storage: fixture.storage)
    #expect(reloaded.snippets.map(\.name) == ["Alpha", "Zeta"])
}

@MainActor
@Test func snippetStoreUpdatesAndRemoves() throws {
    let fixture = try makeTestStorage()
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    let store = SnippetStore(storage: fixture.storage)
    let snippet = Snippet(id: UUID(), name: "Sig", keyword: nil, content: "old")
    try store.add(snippet)
    try store.update(Snippet(id: snippet.id, name: "Sig", keyword: "sig", content: "new"))
    #expect(store.snippets.first?.content == "new")
    try store.remove(id: snippet.id)
    #expect(store.snippets.isEmpty)
}

@MainActor
@Test func snippetStoreQuarantinesCorruptFile() throws {
    let fixture = try makeTestStorage()
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    try Data("not json".utf8).write(to: fixture.storage.snippetsFileURL)
    let store = SnippetStore(storage: fixture.storage)
    #expect(store.snippets.isEmpty)
    #expect(FileManager.default.fileExists(
        atPath: fixture.storage.snippetsFileURL.path + ".corrupt"))
}

@MainActor
@Test func snippetsProviderServesGeneralAndSnippetsModes() async throws {
    let fixture = try makeTestStorage()
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    let store = SnippetStore(storage: fixture.storage)
    try store.add(Snippet(id: UUID(), name: "Email", keyword: "em", content: "a@b.c\nsecond line"))
    let provider = SnippetsProvider(store: store)

    // General mode: only with a term; Ranker does the filtering via keywords.
    #expect(try await provider.results(for: ParsedQuery(mode: .general, term: "")).isEmpty)
    let general = try await provider.results(for: ParsedQuery(mode: .general, term: "em"))
    let row = try #require(general.first)
    #expect(row.action == .copyText("a@b.c\nsecond line"))
    #expect(row.subtitle == "a@b.c")
    #expect(row.badge == "Snippet")
    #expect(row.keywords.contains("Email") && row.keywords.contains("em"))

    // Snippets mode: empty term lists everything.
    let browse = try await provider.results(for: ParsedQuery(mode: .snippets, term: ""))
    #expect(browse.count == 1)
    #expect(Ranker.defaultWeights[.snippets] == 35)
}

@MainActor
@Test func commandsProviderEmitsSnippetsBrowseRow() async throws {
    let provider = CommandsProvider()
    #expect(try await provider.results(for: ParsedQuery(mode: .general, term: "")).isEmpty)
    let results = try await provider.results(for: ParsedQuery(mode: .general, term: "snip"))
    let command = try #require(results.first { $0.id == "command:snippets" })
    #expect(command.action == .enterMode(.snippets))
    #expect(command.providerID == .commands)
}

@Test func escapeExitsSnippetsModeBeforeClosing() {
    #expect(EscapePolicy.action(textIsEmpty: true, stickyMode: .snippets) == .exitMode)
}

/// Snippets are authored data: the user typed them and nothing can regenerate
/// them. A write that fails must not look like it worked, or the in-memory list
/// and the file disagree until the next launch quietly discards the difference.
@MainActor
@Test func snippetStoreDoesNotPublishAMutationThatFailedToPersist() throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("bopop-missing-\(UUID().uuidString)", isDirectory: true)
    // Deliberately NOT created: every write into it fails.
    let storage = Storage(baseDirectory: root)
    let store = SnippetStore(storage: storage)

    #expect(throws: SnippetStore.StoreError.self) {
        try store.add(Snippet(id: UUID(), name: "Sig", keyword: nil, content: "body"))
    }
    #expect(store.snippets.isEmpty)
}

/// A quarantined file still holds the user's snippets under `.corrupt`. Starting
/// empty and writing over the top would strand that copy behind a name they
/// never see, so the store refuses to write until someone deals with it.
@MainActor
@Test func snippetStoreRefusesToWriteAfterQuarantiningAFile() throws {
    let fixture = try makeTestStorage()
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    let garbage = Data("not json".utf8)
    try garbage.write(to: fixture.storage.snippetsFileURL)

    let store = SnippetStore(storage: fixture.storage)

    #expect(!store.isAvailable)
    #expect(store.snippets.isEmpty)
    #expect(throws: SnippetStore.StoreError.storageUnavailable) {
        try store.add(Snippet(id: UUID(), name: "Sig", keyword: nil, content: "body"))
    }
    // The quarantined copy is untouched, and no new file was written over it.
    let quarantined = fixture.storage.snippetsFileURL.path + ".corrupt"
    #expect(try Data(contentsOf: URL(fileURLWithPath: quarantined)) == garbage)
    #expect(!FileManager.default.fileExists(atPath: fixture.storage.snippetsFileURL.path))
}

/// The empty case has to stay writable: a fresh install has no file at all, and
/// that must not be confused with a file that could not be read.
@MainActor
@Test func snippetStoreIsWritableOnAFreshInstall() throws {
    let fixture = try makeTestStorage()
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    let store = SnippetStore(storage: fixture.storage)

    #expect(store.isAvailable)
    try store.add(Snippet(id: UUID(), name: "Sig", keyword: nil, content: "body"))
    #expect(store.snippets.count == 1)
}
