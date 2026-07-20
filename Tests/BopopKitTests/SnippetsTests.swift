import Foundation
import Testing
@testable import BopopKit

@MainActor
@Test func snippetStorePersistsSortedByName() throws {
    let fixture = try makeTestStorage()
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    let store = SnippetStore(storage: fixture.storage)
    store.add(Snippet(id: UUID(), name: "Zeta", keyword: nil, content: "z"))
    store.add(Snippet(id: UUID(), name: "Alpha", keyword: "em", content: "a@b.c"))
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
    store.add(snippet)
    store.update(Snippet(id: snippet.id, name: "Sig", keyword: "sig", content: "new"))
    #expect(store.snippets.first?.content == "new")
    store.remove(id: snippet.id)
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
    store.add(Snippet(id: UUID(), name: "Email", keyword: "em", content: "a@b.c\nsecond line"))
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
