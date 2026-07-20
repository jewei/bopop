import Foundation
import Testing
@testable import BopopKit

@Test func filePayloadExtractsPathsFromFileAndAppResults() {
    let file = SearchResult(
        id: "f", providerID: .files, title: "Notes.txt",
        action: .openFile("/Users/x/Notes.txt"),
        secondaryActions: [.revealFile("/Users/x/Notes.txt")], sortHint: 0)
    #expect(FilePayload.path(for: file) == "/Users/x/Notes.txt")

    let app = SearchResult(
        id: "a", providerID: .apps, title: "Safari",
        action: .openApp("/Applications/Safari.app"), sortHint: 0)
    #expect(FilePayload.path(for: app) == "/Applications/Safari.app")

    let calc = SearchResult(
        id: "c", providerID: .calculator, title: "= 4",
        action: .copyText("4"), sortHint: 0)
    #expect(FilePayload.path(for: calc) == nil)
    #expect(FilePayload.path(for: nil) == nil)
}

@MainActor
@Test func fileResultsCarryRevealSecondaryAction() async throws {
    let root = try makeFilePayloadFixtureDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    try makeFilePayloadFakeBundle(
        at: root.appendingPathComponent("Foo.app", isDirectory: true),
        bundleID: "foo",
        bundleName: "Foo"
    )
    let catalog = AppCatalog(directories: [root], extraApplicationPaths: [])
    await catalog.refreshNow()
    let provider = AppsProvider(catalog: catalog, frecencyFor: { _ in 0 })

    let results = try await provider.results(
        for: ParsedQuery(mode: .general, term: "Foo")
    )

    // `AppCatalog.scan` resolves the fixture path (symlink-canonicalized by
    // FileManager), so the expectation is built from the same scanned
    // `AppInfo.path` used to construct the result, per `AppCatalogTests`'
    // `hasSuffix` pattern rather than a literal path comparison.
    let result = try #require(results.first)
    let scannedApp = try #require(catalog.apps.first)
    #expect(scannedApp.path.hasSuffix("/Foo.app"))
    #expect(result.secondaryActions.contains(.revealFile(scannedApp.path)))
}

@MainActor
@Test func fileSearchResultsCarryRevealSecondaryAction() async throws {
    let path = "/Users/x/Notes.txt"
    let provider = FileSearchProvider { _ in
        [
            FileSearcher.Item(
                path: path,
                displayName: "Notes.txt",
                contentTypeDescription: nil,
                modifiedAt: nil
            )
        ]
    }

    let results = try await provider.results(
        for: ParsedQuery(mode: .fileSearch, term: "notes")
    )

    let result = try #require(results.first)
    #expect(result.secondaryActions.contains(.revealFile(path)))
}

private func makeFilePayloadFixtureDirectory() throws -> URL {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(
        at: root,
        withIntermediateDirectories: true
    )
    return root
}

private func makeFilePayloadFakeBundle(
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
