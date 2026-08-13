import Foundation
import Testing
@testable import Bopop
@testable import BopopKit

private func makeDefaults() -> UserDefaults {
    let suite = "com.oneone.bopop.tests.\(UUID().uuidString)"
    return UserDefaults(suiteName: suite)!
}

/// AppDelegate reads the limit through this static before any SettingsModel
/// exists, so an out-of-range stored value has to be clamped here rather than
/// only in the `@Published` didSet.
@Test func storedClipboardLimitClampsOutOfRangeValues() {
    let defaults = makeDefaults()
    #expect(SettingsModel.storedClipboardLimit(in: defaults) == 100)

    defaults.set(9_999, for: PersistedPreferenceKeys.clipboardLimit)
    #expect(SettingsModel.storedClipboardLimit(in: defaults) == 500)

    defaults.set(1, for: PersistedPreferenceKeys.clipboardLimit)
    #expect(SettingsModel.storedClipboardLimit(in: defaults) == 10)

    defaults.set(-40, for: PersistedPreferenceKeys.clipboardLimit)
    #expect(SettingsModel.storedClipboardLimit(in: defaults) == 10)

    defaults.set(250, for: PersistedPreferenceKeys.clipboardLimit)
    #expect(SettingsModel.storedClipboardLimit(in: defaults) == 250)
}

@Test func storedEnumsFallBackWhenMissingOrUnrecognized() {
    let defaults = makeDefaults()
    #expect(SettingsModel.storedChineseVariant(in: defaults) == .chineseSimplified)
    #expect(SettingsModel.storedSearchEngine(in: defaults) == .google)

    defaults.set("not-a-variant", for: PersistedPreferenceKeys.chineseVariant)
    defaults.set("not-an-engine", for: PersistedPreferenceKeys.searchEngine)
    #expect(SettingsModel.storedChineseVariant(in: defaults) == .chineseSimplified)
    #expect(SettingsModel.storedSearchEngine(in: defaults) == .google)

    defaults.set(TranslationTarget.chineseTraditional.rawValue, for: PersistedPreferenceKeys.chineseVariant)
    defaults.set(SearchEngine.duckDuckGo.rawValue, for: PersistedPreferenceKeys.searchEngine)
    #expect(SettingsModel.storedChineseVariant(in: defaults) == .chineseTraditional)
    #expect(SettingsModel.storedSearchEngine(in: defaults) == .duckDuckGo)
}

@Test func storedCustomSearchesSurvivesGarbageWithoutThrowing() throws {
    let defaults = makeDefaults()
    #expect(SettingsModel.storedCustomSearches(in: defaults).isEmpty)

    defaults.set(Data("not json".utf8), for: PersistedPreferenceKeys.customSearchesData)
    #expect(SettingsModel.storedCustomSearches(in: defaults).isEmpty)

    let search = CustomWebSearch(
        id: UUID(), name: "Docs", keyword: "d", urlTemplate: "https://example.com/?q={query}"
    )
    defaults.set(
        try JSONEncoder().encode([search]),
        for: PersistedPreferenceKeys.customSearchesData
    )
    #expect(SettingsModel.storedCustomSearches(in: defaults) == [search])
}

@MainActor
private func makeModel(
    defaults: UserDefaults,
    storage: Storage,
    hotkeyManager: any HotkeyRegistering = HotkeyManager()
) -> SettingsModel {
    SettingsModel(
        hotkeyManager: hotkeyManager,
        clipboardStore: ClipboardStore(storage: storage),
        snippetStore: SnippetStore(storage: storage),
        visibilityStore: VisibilityStore(storage: storage),
        rateStore: RateStore(storage: storage),
        storage: storage,
        defaults: defaults
    )
}

@MainActor
private func withModel(
    hotkeyManager: any HotkeyRegistering = HotkeyManager(),
    _ body: (SettingsModel) throws -> Void
) throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("bopop-settings-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let storage = Storage(baseDirectory: root)
    try storage.ensureDirectories()
    try body(
        makeModel(
            defaults: makeDefaults(),
            storage: storage,
            hotkeyManager: hotkeyManager
        )
    )
}

/// A rejected custom search used to return `false` and vanish — the row stayed
/// on screen with no indication of what was wrong with it.
@MainActor
@Test func rejectedCustomSearchReportsWhyItWasRejected() throws {
    try withModel { model in
        model.addCustomSearch(name: " ", keyword: "j", urlTemplate: "https://x/?q={query}")
        #expect(model.customSearchError == .nameMissing)
        #expect(model.customSearches.isEmpty)

        model.addCustomSearch(name: "Jira", keyword: "", urlTemplate: "https://x/?q={query}")
        #expect(model.customSearchError == .keywordMissing)

        model.addCustomSearch(name: "Jira", keyword: "a b", urlTemplate: "https://x/?q={query}")
        #expect(model.customSearchError == .keywordHasWhitespace)

        model.addCustomSearch(name: "Jira", keyword: "f", urlTemplate: "https://x/?q={query}")
        #expect(model.customSearchError == .keywordReserved)

        model.addCustomSearch(name: "Jira", keyword: "j", urlTemplate: "https://x/?q=term")
        #expect(model.customSearchError == .templateMissingQueryToken)

        model.addCustomSearch(name: "Jira", keyword: "j", urlTemplate: "https://x/?q={query}")
        #expect(model.customSearchError == nil)
        #expect(model.customSearches.count == 1)

        model.addCustomSearch(name: "Jira 2", keyword: "J", urlTemplate: "https://y/?q={query}")
        #expect(model.customSearchError == .keywordTaken)
        #expect(model.customSearches.count == 1)
    }
}

/// The per-field messages restate `CustomWebSearch.isValid`'s conditions one at
/// a time, so the two can drift: the form would accept a search the provider
/// then treats as invalid, or reject one it would have accepted.
@MainActor
@Test func validationAgreesWithCustomWebSearchIsValid() throws {
    let cases: [(String, String, String)] = [
        ("Jira", "j", "https://x/?q={query}"),
        ("", "j", "https://x/?q={query}"),
        ("   ", "j", "https://x/?q={query}"),
        ("Jira", "", "https://x/?q={query}"),
        ("Jira", "a b", "https://x/?q={query}"),
        ("Jira", "f", "https://x/?q={query}"),
        ("Jira", "T", "https://x/?q={query}"),
        ("Jira", ":smile", "https://x/?q={query}"),
        ("Jira", "j", "https://x/?q=term"),
        ("Jira", "j", "")
    ]

    for (name, keyword, template) in cases {
        try withModel { model in
            model.addCustomSearch(name: name, keyword: keyword, urlTemplate: template)
            let search = CustomWebSearch(
                id: UUID(), name: name, keyword: keyword, urlTemplate: template
            )
            #expect(
                (model.customSearchError == nil) == search.isValid,
                "disagreement for name=\(name) keyword=\(keyword) template=\(template)"
            )
        }
    }
}

@MainActor
@Test func rejectedSnippetReportsWhyItWasRejected() throws {
    try withModel { model in
        model.addSnippet(name: "  ", keyword: "", content: "body")
        #expect(model.snippetError == .nameMissing)
        #expect(model.snippets.isEmpty)

        model.addSnippet(name: "Sig", keyword: "", content: "   ")
        #expect(model.snippetError == .contentMissing)

        model.addSnippet(name: "Sig", keyword: "", content: "body")
        #expect(model.snippetError == nil)
        #expect(model.snippets.count == 1)
    }
}

/// The error has to clear once the offending value changes, or a stale message
/// sits under a form the user has already corrected.
@MainActor
@Test func validationErrorsClearOnTheNextSuccessfulAdd() throws {
    try withModel { model in
        model.addSnippet(name: "", keyword: "", content: "")
        #expect(model.snippetError != nil)
        model.clearSnippetError()
        #expect(model.snippetError == nil)

        model.addCustomSearch(name: "", keyword: "", urlTemplate: "")
        #expect(model.customSearchError != nil)
        model.clearCustomSearchError()
        #expect(model.customSearchError == nil)
    }
}

/// A folder that has been renamed or unmounted is silently skipped at query
/// time, so Settings is the only place that can tell the user it is dead.
@MainActor
@Test func missingFileSearchFoldersAreFlagged() throws {
    try withModel { model in
        let existing = FileManager.default.temporaryDirectory
            .appendingPathComponent("bopop-folder-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: existing, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: existing) }
        let missing = existing.appendingPathComponent("gone", isDirectory: true)

        model.addFileSearchFolders([existing.path, missing.path])

        #expect(!model.isFileSearchFolderMissing(existing.path))
        #expect(model.isFileSearchFolderMissing(missing.path))
    }
}

@MainActor
@Test func disablingCurrencyClearsTheProvidersLiveRateStore() throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("bopop-settings-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }

    let storage = Storage(baseDirectory: root)
    try storage.ensureDirectories()
    let rateStore = RateStore(storage: storage)
    rateStore.save(
        rates: ["EUR": 1, "USD": 1.08],
        fetchedAt: Date(timeIntervalSince1970: 1_000)
    )
    _ = rateStore.cached()

    let defaults = makeDefaults()
    defaults.set(true, for: PersistedPreferenceKeys.currencyEnabled)
    let model = SettingsModel(
        hotkeyManager: HotkeyManager(),
        clipboardStore: ClipboardStore(storage: storage),
        snippetStore: SnippetStore(storage: storage),
        visibilityStore: VisibilityStore(storage: storage),
        rateStore: rateStore,
        storage: storage,
        defaults: defaults
    )

    model.setCurrencyEnabled(false)

    #expect(rateStore.cached() == nil)
    #expect(!FileManager.default.fileExists(atPath: storage.ratesFileURL.path))
}

/// A quarantined snippets file must be visible in Settings before the user
/// composes anything, and a save attempt must refuse rather than write over the
/// recovered copy.
@MainActor
@Test func quarantinedSnippetsFileMakesSettingsReadOnly() throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("bopop-settings-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let storage = Storage(baseDirectory: root)
    try storage.ensureDirectories()
    try Data("not json".utf8).write(to: storage.snippetsFileURL)

    let model = makeModel(defaults: makeDefaults(), storage: storage)

    #expect(!model.snippetsAvailable)

    let added = model.addSnippet(name: "Sig", keyword: "", content: "body")

    #expect(!added)
    #expect(model.snippetError == .storageUnavailable)
    #expect(model.snippets.isEmpty)
    #expect(!FileManager.default.fileExists(atPath: storage.snippetsFileURL.path))
}

private final class StubHotkeyRegistrar: HotkeyRegistering {
    var outcomes: [HotkeyRegistrationOutcome]
    private(set) var registered: [HotkeyConfig] = []
    private(set) var unregisterCount = 0

    init(_ outcomes: [HotkeyRegistrationOutcome]) {
        self.outcomes = outcomes
    }

    func register(_ config: HotkeyConfig) -> HotkeyRegistrationOutcome {
        registered.append(config)
        return outcomes.isEmpty ? .registered : outcomes.removeFirst()
    }

    func unregister() {
        unregisterCount += 1
    }
}

@MainActor
@Test
func registrationFailureIsSurfacedAndRecheckPublishesRecovery() throws {
    let registrar = StubHotkeyRegistrar([.registered])
    try withModel(hotkeyManager: registrar) { model in
        model.setHotkeyRegistrationOutcome(.registrationFailed(-50))
        #expect(
            model.hotkeyRegistrationOutcome?.failureMessage
                == "Bopop couldn't register this shortcut (Carbon status -50)."
        )

        model.recheckConflict()
        #expect(model.hotkeyRegistrationOutcome == .registered)
        #expect(registrar.registered == [model.hotkey])
    }
}

@MainActor
@Test
func recordingRegistersExactlyOnceAndPublishesItsOutcome() throws {
    let registrar = StubHotkeyRegistrar([.registrationFailed(-9878)])
    try withModel(hotkeyManager: registrar) { model in
        model.isRecording = true
        model.hotkey = HotkeyConfig(keyCode: 12, modifiers: [.command, .option])
        #expect(registrar.registered.isEmpty)

        model.isRecording = false

        #expect(registrar.unregisterCount == 1)
        #expect(registrar.registered == [model.hotkey])
        #expect(model.hotkeyRegistrationOutcome == .registrationFailed(-9878))
    }
}
