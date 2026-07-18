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

@MainActor
@Test
func appsProviderReturnsFrecentAppsForEmptyTerm() async throws {
    let root = try makeAppFixtureDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    try makeLetteredBundles(in: root)
    let catalog = AppCatalog(directories: [root])
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
        frecencyFor: { scores[$0, default: 0] }
    )

    let results = try await provider.results(
        for: ParsedQuery(mode: .general, term: "")
    )

    #expect(results.map(\.id) == [
        "app:b", "app:a", "app:c", "app:d", "app:e", "app:f"
    ])
}

@MainActor
@Test
func appsProviderReturnsAllAppsForNonemptyTerm() async throws {
    let root = try makeAppFixtureDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    try makeLetteredBundles(in: root)
    let catalog = AppCatalog(directories: [root])
    await catalog.refreshNow()
    let provider = AppsProvider(catalog: catalog, frecencyFor: { _ in 0 })

    let results = try await provider.results(
        for: ParsedQuery(mode: .general, term: "anything")
    )

    #expect(results.map(\.id) == [
        "app:a", "app:b", "app:c", "app:d",
        "app:e", "app:f", "app:g", "app:h"
    ])
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
