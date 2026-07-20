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

@Test
func appendScriptLogTrimsOversizedFileKeepingNewestContent() throws {
    let root = makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let storage = Storage(baseDirectory: root)
    try storage.ensureDirectories()

    // Synthesize a scripts.log already past the 1 MB cap. Every line
    // shares a fixed "LINE" prefix (rather than a uniform filler byte) so
    // trimming-to-a-newline-boundary is actually verifiable: a correctly
    // aligned tail's first line must start with the full "LINE" prefix,
    // whereas a naive byte-offset cut landing mid-line would produce a
    // fragment like "NE00042..." missing its leading characters. A
    // recognizable marker on the very last line confirms the newest
    // content survives trimming.
    let fileManager = FileManager.default
    let paddingLine = "LINE" + String(repeating: "x", count: 196) + "\n"
    var oversized = String(repeating: paddingLine, count: 6_000)
    oversized += "MARKER-newest-line\n"
    try Data(oversized.utf8).write(to: storage.scriptsLogURL)
    let sizeBeforeAppend = try fileManager.attributesOfItem(
        atPath: storage.scriptsLogURL.path
    )[.size] as? Int
    #expect((sizeBeforeAppend ?? 0) > 1_048_576)

    storage.appendScriptLog("trigger trim")

    let attributes = try fileManager.attributesOfItem(atPath: storage.scriptsLogURL.path)
    let sizeAfter = try #require(attributes[.size] as? Int)
    let contents = try String(contentsOf: storage.scriptsLogURL, encoding: .utf8)

    // Shrunk well below the original size, comfortably above (but close
    // to) the 256 KB trim target once the newly-appended line is added.
    #expect(sizeAfter < 1_048_576)
    #expect(sizeAfter < sizeBeforeAppend ?? 0)
    // Newest content (both the pre-existing marker line and the just
    // appended entry) must survive trimming.
    #expect(contents.contains("MARKER-newest-line"))
    #expect(contents.contains("trigger trim"))
    // Trimming must not start mid-line: the retained tail begins with a
    // complete "LINE..." line, not a fragment of one that a raw byte-count
    // cut would have produced.
    #expect(contents.hasPrefix("LINE"))
    #expect(try permissions(at: storage.scriptsLogURL) == 0o600)
}

@Test
func appendScriptLogDoesNotTrimWhenUnderLimit() throws {
    let root = makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let storage = Storage(baseDirectory: root)
    try storage.ensureDirectories()

    storage.appendScriptLog("first")
    storage.appendScriptLog("second")

    let contents = try String(contentsOf: storage.scriptsLogURL, encoding: .utf8)
    #expect(contents.contains("first"))
    #expect(contents.contains("second"))
}

private func makeTemporaryDirectory() -> URL {
    FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
}

private func permissions(at url: URL) throws -> Int {
    let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
    return (attributes[.posixPermissions] as? NSNumber)?.intValue ?? -1
}
