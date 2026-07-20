import Foundation
import Testing
@testable import BopopKit

private struct Sample: Codable, Equatable {
    let name: String
    let count: Int
}

@Test
func saveAndLoadRoundTrip() throws {
    let root = makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let storage = Storage(baseDirectory: root)
    try storage.ensureDirectories()

    let expected = Sample(name: "demo", count: 3)
    try storage.save(expected, version: 1, to: storage.usageFileURL)

    let loaded = storage.load(Sample.self, expectedVersion: 1, from: storage.usageFileURL)
    #expect(loaded == expected)
}

@Test
func storagePermissionsArePrivate() throws {
    let root = makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let storage = Storage(baseDirectory: root)
    try storage.ensureDirectories()
    try storage.save(Sample(name: "private", count: 1), version: 1, to: storage.usageFileURL)

    #expect(try permissions(at: storage.baseDirectory) == 0o700)
    #expect(try permissions(at: storage.scriptsDirectory) == 0o700)
    #expect(try permissions(at: storage.usageFileURL) == 0o600)
}

@Test
func brandImageURLIsUnderBaseDirectory() {
    let root = makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let storage = Storage(baseDirectory: root)

    #expect(storage.brandImageURL == root.appendingPathComponent("brand.png"))
    #expect(storage.brandImageURL.deletingLastPathComponent() == storage.baseDirectory)
}

@Test
func corruptFileIsQuarantinedAndCanBeReplaced() throws {
    let root = makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let storage = Storage(baseDirectory: root)
    try storage.ensureDirectories()
    try Data("not json".utf8).write(to: storage.usageFileURL)

    let loaded = storage.load(Sample.self, expectedVersion: 1, from: storage.usageFileURL)
    let corruptURL = storage.usageFileURL.appendingPathExtension("corrupt")
    #expect(loaded == nil)
    #expect(!FileManager.default.fileExists(atPath: storage.usageFileURL.path))
    #expect(FileManager.default.fileExists(atPath: corruptURL.path))

    let expected = Sample(name: "replacement", count: 2)
    try storage.save(expected, version: 1, to: storage.usageFileURL)
    let replacement = storage.load(
        Sample.self,
        expectedVersion: 1,
        from: storage.usageFileURL
    )
    #expect(replacement == expected)
}

@Test
func versionMismatchIsQuarantined() throws {
    let root = makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let storage = Storage(baseDirectory: root)
    try storage.ensureDirectories()
    try storage.save(Sample(name: "old", count: 1), version: 1, to: storage.usageFileURL)

    let loaded = storage.load(Sample.self, expectedVersion: 2, from: storage.usageFileURL)
    let corruptURL = storage.usageFileURL.appendingPathExtension("corrupt")
    #expect(loaded == nil)
    #expect(!FileManager.default.fileExists(atPath: storage.usageFileURL.path))
    #expect(FileManager.default.fileExists(atPath: corruptURL.path))
}

@Test
func missingFileHasNoSideEffects() {
    let root = makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let storage = Storage(baseDirectory: root)

    let loaded = storage.load(Sample.self, expectedVersion: 1, from: storage.usageFileURL)
    let corruptURL = storage.usageFileURL.appendingPathExtension("corrupt")
    #expect(loaded == nil)
    #expect(!FileManager.default.fileExists(atPath: corruptURL.path))
}

private func makeTemporaryDirectory() -> URL {
    FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
}

private func permissions(at url: URL) throws -> Int {
    let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
    return (attributes[.posixPermissions] as? NSNumber)?.intValue ?? -1
}
