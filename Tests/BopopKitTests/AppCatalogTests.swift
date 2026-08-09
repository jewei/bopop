import Foundation
import Testing
@testable import BopopKit

@Test
func appCatalogScansOnlyTopLevelAndOneNestedLevel() async throws {
    let root = try makeAppFixtureDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    try makeFakeBundle(
        at: root.appendingPathComponent("Foo.app", isDirectory: true),
        bundleID: "foo",
        bundleName: "Foo"
    )
    try makeFakeBundle(
        at: root.appendingPathComponent("Sub/Bar.app", isDirectory: true),
        bundleID: "bar",
        bundleName: "Bar"
    )
    try makeFakeBundle(
        at: root.appendingPathComponent("Sub/Deeper/Baz.app", isDirectory: true),
        bundleID: "baz",
        bundleName: "Baz"
    )
    try Data("notes".utf8).write(
        to: root.appendingPathComponent("notes.txt")
    )
    try FileManager.default.createDirectory(
        at: root.appendingPathComponent("Random", isDirectory: true),
        withIntermediateDirectories: true
    )

    let apps = await AppCatalog.scan(directories: [root])

    #expect(apps.map(\.name) == ["Bar", "Foo"])
}

@Test
func appCatalogDeduplicatesBundleIDsInDirectoryOrder() async throws {
    let firstRoot = try makeAppFixtureDirectory()
    let secondRoot = try makeAppFixtureDirectory()
    defer {
        try? FileManager.default.removeItem(at: firstRoot)
        try? FileManager.default.removeItem(at: secondRoot)
    }
    let firstURL = firstRoot.appendingPathComponent("First.app", isDirectory: true)
    try makeFakeBundle(
        at: firstURL,
        bundleID: "shared",
        bundleName: "First"
    )
    try makeFakeBundle(
        at: secondRoot.appendingPathComponent("Second.app", isDirectory: true),
        bundleID: "shared",
        bundleName: "Second"
    )

    let apps = await AppCatalog.scan(directories: [firstRoot, secondRoot])

    #expect(apps.count == 1)
    #expect(apps.first?.name == "First")
    #expect(apps.first?.path.hasSuffix("/First.app") == true)
}

@Test
func appCatalogUsesDifferingBundleNameAsKeyword() async throws {
    let root = try makeAppFixtureDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    try makeFakeBundle(
        at: root.appendingPathComponent("Foo.app", isDirectory: true),
        bundleID: "foo",
        bundleName: "FooCore"
    )
    try makeFakeBundle(
        at: root.appendingPathComponent("Bar.app", isDirectory: true),
        bundleID: "bar",
        bundleName: "bar"
    )

    let apps = await AppCatalog.scan(directories: [root])

    #expect(apps.first(where: { $0.name == "Foo" })?.keywords == ["FooCore"])
    #expect(apps.first(where: { $0.name == "Bar" })?.keywords == [])
}

@Test
func appCatalogIncludesExistingExtraApplicationPaths() async throws {
    let root = try makeAppFixtureDirectory()
    let extraRoot = try makeAppFixtureDirectory()
    defer {
        try? FileManager.default.removeItem(at: root)
        try? FileManager.default.removeItem(at: extraRoot)
    }
    try makeFakeBundle(
        at: root.appendingPathComponent("Foo.app", isDirectory: true),
        bundleID: "foo",
        bundleName: "Foo"
    )
    let extraURL = extraRoot.appendingPathComponent("Extra.app", isDirectory: true)
    try makeFakeBundle(at: extraURL, bundleID: "extra", bundleName: "Extra")

    let apps = await AppCatalog.scan(
        directories: [root],
        extraApplicationPaths: [extraURL.path, "/nonexistent/Nope.app"]
    )

    #expect(apps.map(\.name) == ["Extra", "Foo"])
}

@MainActor
@Test
func newlyInstalledAppAppearsAfterPresentationRefresh() async throws {
    let root = try makeAppFixtureDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    try makeFakeBundle(
        at: root.appendingPathComponent("Existing.app", isDirectory: true),
        bundleID: "existing",
        bundleName: "Existing"
    )
    let catalog = AppCatalog(
        directories: [root],
        extraApplicationPaths: [],
        staleAfter: 300
    )
    await catalog.refreshNow()
    let provider = AppsProvider(catalog: catalog, frecencyFor: { _ in [:] })
    let lateURL = root.appendingPathComponent("LateArrival.app", isDirectory: true)
    try makeFakeBundle(
        at: lateURL,
        bundleID: "late-arrival",
        bundleName: "LateArrival"
    )

    let changed = await catalog.refreshNow()
    let results = try await provider.results(
        for: ParsedQuery(mode: .apps, term: "LateArrival")
    )

    #expect(changed)
    #expect(results.count == 1)
    #expect(results.first?.id == "app:late-arrival")
    #expect(results.first?.title == "LateArrival")
    if case .openApp(let path) = results.first?.action {
        #expect(path.hasSuffix("/LateArrival.app"))
    } else {
        Issue.record("LateArrival result should open its app bundle")
    }
}

@MainActor
@Test
func removedAppDisappearsAfterPresentationRefresh() async throws {
    let root = try makeAppFixtureDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let removedURL = root.appendingPathComponent("Removed.app", isDirectory: true)
    try makeFakeBundle(
        at: removedURL,
        bundleID: "removed",
        bundleName: "Removed"
    )
    let catalog = AppCatalog(directories: [root], extraApplicationPaths: [])
    await catalog.refreshNow()
    let provider = AppsProvider(catalog: catalog, frecencyFor: { _ in [:] })
    try FileManager.default.removeItem(at: removedURL)

    let changed = await catalog.refreshNow()
    let results = try await provider.results(
        for: ParsedQuery(mode: .apps, term: "Removed")
    )

    #expect(changed)
    #expect(results.isEmpty)
}

@MainActor
@Test
func forcedRefreshReportsNoChangeForIdenticalSnapshot() async {
    let app = AppInfo(
        bundleID: "unchanged",
        name: "Unchanged",
        path: "/Applications/Unchanged.app",
        keywords: []
    )
    let catalog = AppCatalog(
        directories: [],
        extraApplicationPaths: [],
        scanner: { _, _ in [app] }
    )

    let firstChanged = await catalog.refreshNow()
    let secondChanged = await catalog.refreshNow()

    #expect(firstChanged)
    #expect(!secondChanged)
}

@MainActor
@Test
func forcedRefreshDuringInFlightScanQueuesFollowUpScan() async {
    let existing = AppInfo(
        bundleID: "existing",
        name: "Existing",
        path: "/Applications/Existing.app",
        keywords: []
    )
    let late = AppInfo(
        bundleID: "late-arrival",
        name: "LateArrival",
        path: "/Applications/LateArrival.app",
        keywords: []
    )
    let probe = AppCatalogScanProbe(firstResult: [existing], laterResult: [existing, late])
    let catalog = AppCatalog(
        directories: [],
        extraApplicationPaths: [],
        scanner: { _, _ in await probe.scan() }
    )

    catalog.refreshIfStale()
    await probe.waitUntilFirstScanStarts()
    let forcedRefresh = Task { await catalog.refreshNow() }
    while catalog.forcedRefreshGeneration == 0 {
        await Task.yield()
    }
    await probe.releaseFirstScan()

    let changed = await forcedRefresh.value

    #expect(changed)
    #expect(await probe.invocationCount == 2)
    #expect(catalog.apps == [existing, late])
}

@MainActor
@Test
func appsProviderReturnsFrecentAppsForEmptyTerm() async throws {
    let root = try makeAppFixtureDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    try makeLetteredBundles(in: root)
    let catalog = AppCatalog(directories: [root], extraApplicationPaths: [])
    await catalog.refreshNow()
    let scores = [
        "app:b": 10.0,
        "app:a": 1.0,
        "app:c": 1.0,
        "app:d": 1.0,
        "app:e": 1.0,
        "app:f": 1.0,
        "app:g": 1.0,
        "app:h": 0.0
    ]
    let provider = AppsProvider(
        catalog: catalog,
        frecencyFor: { ids in ids.reduce(into: [:]) { $0[$1] = scores[$1, default: 0] } }
    )

    let results = try await provider.results(
        for: ParsedQuery(mode: .general, term: "")
    )

    #expect(results.map(\.id) == [
        "app:b", "app:a", "app:c", "app:d", "app:e", "app:f"
    ])
}

// Task 9: providers now pre-filter a nonempty term by Ranker tier
// (name+keywords) before mapping, rather than returning the whole catalog
// unfiltered and relying entirely on the caller's later Ranker.rank pass.
// The lettered fixture's bundle names double as their only searchable
// text (bundleName always equals name, so keywords stay empty), so a term
// that exactly matches one letter is the clean way to exercise the filter.

@MainActor
@Test
func appsProviderPreFiltersNonemptyTermByTier() async throws {
    let root = try makeAppFixtureDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    try makeLetteredBundles(in: root)
    let catalog = AppCatalog(directories: [root], extraApplicationPaths: [])
    await catalog.refreshNow()
    let provider = AppsProvider(catalog: catalog, frecencyFor: { _ in [:] })

    let results = try await provider.results(
        for: ParsedQuery(mode: .general, term: "b")
    )

    #expect(results.map(\.id) == ["app:b"])
    // "B" is the second app in catalog order (A, B, C, ...) — sortHint
    // must stay tied to the FULL catalog's index, not the filtered list's.
    #expect(results.first?.sortHint == 1)
    #expect(results.first?.subtitle != nil)
    #expect(results.first?.badge == "Apps")
}

@MainActor
@Test
func appsProviderServesAppsMode() async throws {
    let root = try makeAppFixtureDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    try makeLetteredBundles(in: root)
    let catalog = AppCatalog(directories: [root], extraApplicationPaths: [])
    await catalog.refreshNow()
    let provider = AppsProvider(catalog: catalog, frecencyFor: { _ in [:] })

    let results = try await provider.results(
        for: ParsedQuery(mode: .apps, term: "g")
    )

    #expect(results.map(\.id) == ["app:g"])
    #expect(results.first?.sortHint == 6)
}

@MainActor
@Test
func appsProviderPreFilterIsRankerNoOp() async throws {
    let root = try makeAppFixtureDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    try makeLetteredBundles(in: root)
    let catalog = AppCatalog(directories: [root], extraApplicationPaths: [])
    await catalog.refreshNow()
    let provider = AppsProvider(catalog: catalog, frecencyFor: { _ in [:] })
    let term = "d"

    let filtered = try await provider.results(for: ParsedQuery(mode: .general, term: term))

    // Reconstruct what the provider would have returned before the
    // pre-filter (the whole catalog, unfiltered) using the same result
    // shape AppsProvider builds, and rank both through Ranker.rank the way
    // QueryEngine does. The pre-filter is meant to be a pure hot-path
    // optimization — Ranker discards the same rows either way — so ranking
    // the (much smaller) filtered set must equal ranking the full catalog.
    let unfiltered = catalog.apps.enumerated().map { index, app in
        SearchResult(
            id: "app:\(app.bundleID ?? app.path)",
            providerID: .apps,
            title: app.name,
            subtitle: (app.path as NSString).abbreviatingWithTildeInPath,
            icon: .appBundle(app.path),
            keywords: app.keywords,
            action: .openApp(app.path),
            secondaryActions: [.copyText(app.path), .revealFile(app.path)],
            sortHint: index
        )
    }

    let rankedFiltered = Ranker.rank(
        filtered, query: term, frecencyFor: { _ in 0 }, providerWeights: Ranker.defaultWeights
    )
    let rankedUnfiltered = Ranker.rank(
        unfiltered, query: term, frecencyFor: { _ in 0 }, providerWeights: Ranker.defaultWeights
    )

    #expect(!rankedFiltered.isEmpty)
    #expect(rankedFiltered.count < catalog.apps.count)
    #expect(rankedFiltered.map(\.id) == rankedUnfiltered.map(\.id))
}

private actor AppCatalogScanProbe {
    let firstResult: [AppInfo]
    let laterResult: [AppInfo]
    private(set) var invocationCount = 0
    private var firstScanStartedWaiters: [CheckedContinuation<Void, Never>] = []
    private var firstScanRelease: CheckedContinuation<Void, Never>?

    init(firstResult: [AppInfo], laterResult: [AppInfo]) {
        self.firstResult = firstResult
        self.laterResult = laterResult
    }

    func scan() async -> [AppInfo] {
        invocationCount += 1
        guard invocationCount == 1 else {
            return laterResult
        }

        let waiters = firstScanStartedWaiters
        firstScanStartedWaiters = []
        for waiter in waiters {
            waiter.resume()
        }
        await withCheckedContinuation { continuation in
            firstScanRelease = continuation
        }
        return firstResult
    }

    func waitUntilFirstScanStarts() async {
        guard invocationCount == 0 else {
            return
        }
        await withCheckedContinuation { continuation in
            firstScanStartedWaiters.append(continuation)
        }
    }

    func releaseFirstScan() {
        firstScanRelease?.resume()
        firstScanRelease = nil
    }
}

private func makeAppFixtureDirectory() throws -> URL {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(
        at: root,
        withIntermediateDirectories: true
    )
    return root
}

private func makeFakeBundle(
    at bundleURL: URL,
    bundleID: String,
    bundleName: String
) throws {
    let contentsURL = bundleURL.appendingPathComponent("Contents", isDirectory: true)
    try FileManager.default.createDirectory(
        at: contentsURL,
        withIntermediateDirectories: true
    )
    let propertyList: [String: Any] = [
        "CFBundleIdentifier": bundleID,
        "CFBundleName": bundleName,
        "CFBundlePackageType": "APPL"
    ]
    let data = try PropertyListSerialization.data(
        fromPropertyList: propertyList,
        format: .xml,
        options: 0
    )
    try data.write(to: contentsURL.appendingPathComponent("Info.plist"))
}

private func makeLetteredBundles(in root: URL) throws {
    for letter in ["a", "b", "c", "d", "e", "f", "g", "h"] {
        try makeFakeBundle(
            at: root.appendingPathComponent("\(letter.uppercased()).app"),
            bundleID: letter,
            bundleName: letter.uppercased()
        )
    }
}
