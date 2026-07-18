import Foundation
import Testing
@testable import BopopKit

@MainActor
@Test
func usageStoreRecordsHits() throws {
    let fixture = try makeUsageStorage()
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    let date = Date(timeIntervalSinceReferenceDate: 1_000_000)
    let store = UsageStore(storage: fixture.storage, now: { date })

    store.record("app:foo")
    store.record("app:foo")

    #expect(abs(store.score("app:foo") - 2) < 1e-9)
}

@MainActor
@Test
func usageStoreDecaysWithFourteenDayHalfLife() throws {
    let fixture = try makeUsageStorage()
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    let recordedAt = Date(timeIntervalSinceReferenceDate: 1_000_000)
    var currentDate = recordedAt
    let store = UsageStore(storage: fixture.storage, now: { currentDate })

    store.record("app:foo")
    store.record("app:foo")
    currentDate = recordedAt.addingTimeInterval(14 * 86_400)
    #expect(abs(store.score("app:foo") - 1) < 1e-9)

    currentDate = recordedAt.addingTimeInterval(28 * 86_400)
    #expect(abs(store.score("app:foo") - 0.5) < 1e-9)
}

@MainActor
@Test
func usageStoreReturnsZeroForUnknownID() throws {
    let fixture = try makeUsageStorage()
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    let store = UsageStore(storage: fixture.storage)

    #expect(store.score("app:missing") == 0)
}

@MainActor
@Test
func usageStoreEvictsLowestScoreBeyondBound() throws {
    let fixture = try makeUsageStorage()
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    var currentDate = Date(timeIntervalSinceReferenceDate: 1_000_000)
    let store = UsageStore(
        storage: fixture.storage,
        now: { currentDate },
        maxEntries: 3
    )

    store.record("app:oldest")
    currentDate.addTimeInterval(86_400)
    store.record("app:middle")
    currentDate.addTimeInterval(86_400)
    store.record("app:recent")
    currentDate.addTimeInterval(86_400)
    store.record("app:newest")

    #expect(store.score("app:oldest") == 0)
    #expect(store.score("app:middle") > 0)
    #expect(store.score("app:recent") > 0)
    #expect(store.score("app:newest") > 0)
}

@MainActor
@Test
func usageStorePersistsRecords() throws {
    let fixture = try makeUsageStorage()
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    let date = Date(timeIntervalSinceReferenceDate: 1_000_000)
    let firstStore = UsageStore(storage: fixture.storage, now: { date })
    firstStore.record("app:foo")

    let secondStore = UsageStore(storage: fixture.storage, now: { date })

    #expect(abs(secondStore.score("app:foo") - 1) < 1e-9)
}

private func makeUsageStorage() throws -> (root: URL, storage: Storage) {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    let storage = Storage(baseDirectory: root)
    try storage.ensureDirectories()
    return (root, storage)
}
