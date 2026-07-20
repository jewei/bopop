import Foundation
@testable import BopopKit

/// Fresh on-disk `Storage` rooted in a unique temp directory, with its
/// directories already created — the fixture every persistence-backed test
/// (clipboard, snippets, usage, currency-rate cache, …) needs before it can
/// construct the store under test. Callers are responsible for cleaning up
/// `root` (typically via `defer { try? FileManager.default.removeItem(at:) }`).
func makeTestStorage() throws -> (root: URL, storage: Storage) {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    let storage = Storage(baseDirectory: root)
    try storage.ensureDirectories()
    return (root, storage)
}
