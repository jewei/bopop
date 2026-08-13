import Foundation

@MainActor
public final class UsageStore {
    private static let version = 1
    private static let maximumHits = 999
    private static let halfLifeInDays = 14.0
    private static let secondsPerDay = 86_400.0

    private let storage: Storage
    private let now: () -> Date
    private let maxEntries: Int
    private var entries: [String: Entry]
    private let saveEntries: ([String: Entry]) throws -> Void
    public private(set) var persistenceError: PersistenceFailure?

    public convenience init(
        storage: Storage,
        now: @escaping () -> Date = Date.init,
        maxEntries: Int = 500
    ) {
        self.init(storage: storage, now: now, maxEntries: maxEntries) { entries in
            try storage.save(entries, version: UsageStore.version, to: storage.usageFileURL)
        }
    }

    init(
        storage: Storage,
        now: @escaping () -> Date = Date.init,
        maxEntries: Int = 500,
        saveEntries: @escaping ([String: Entry]) throws -> Void
    ) {
        self.storage = storage
        self.now = now
        self.maxEntries = max(0, maxEntries)
        self.saveEntries = saveEntries
        persistenceError = nil
        let loadedEntries = storage.load(
            [String: Entry].self,
            expectedVersion: Self.version,
            from: storage.usageFileURL
        ) ?? [:]
        entries = Self.sanitized(loadedEntries)
        evictEntriesIfNeeded(at: now())
        // Write the cleaned table back rather than only holding it in memory:
        // otherwise a rejected or evicted record stays on disk and a later
        // launch with a larger cap resurrects it into the ranking.
        if entries != loadedEntries {
            do {
                try saveEntries(entries)
            } catch {
                persistenceError = PersistenceFailure(error.localizedDescription)
            }
        }
    }

    @discardableResult
    public func record(_ id: String) -> Result<Void, PersistenceFailure> {
        let previousEntries = entries
        let currentDate = now()
        let previousHits = entries[id]?.hits ?? 0
        let hits = previousHits >= Self.maximumHits
            ? Self.maximumHits
            : previousHits + 1
        entries[id] = Entry(hits: hits, lastUsed: currentDate)
        evictEntriesIfNeeded(at: currentDate)
        do {
            try saveEntries(entries)
            return .success(())
        } catch {
            entries = previousEntries
            let failure = PersistenceFailure(error.localizedDescription)
            persistenceError = failure
            return .failure(failure)
        }
    }

    public func score(_ id: String) -> Double {
        guard let entry = entries[id] else {
            return 0
        }
        return score(entry, at: now())
    }

    /// Scores every id in one pass, sharing a single `now()` read across the
    /// whole batch rather than one per id — the MainActor-side half of
    /// `BatchFrecencyLookup`, so a caller off the main actor only needs a
    /// single `MainActor.run` hop to score an entire catalog.
    public func scores(for ids: [String]) -> [String: Double] {
        let currentDate = now()
        return ids.reduce(into: [String: Double]()) { result, id in
            guard let entry = entries[id] else {
                result[id] = 0
                return
            }
            result[id] = score(entry, at: currentDate)
        }
    }

    private func evictEntriesIfNeeded(at date: Date) {
        guard entries.count > maxEntries else {
            return
        }

        let evictionCount = entries.count - maxEntries
        let idsToEvict = entries.sorted { lhs, rhs in
            let lhsScore = score(lhs.value, at: date)
            let rhsScore = score(rhs.value, at: date)
            if lhsScore != rhsScore {
                return lhsScore < rhsScore
            }
            return lhs.key < rhs.key
        }.prefix(evictionCount).map(\.key)

        for id in idsToEvict {
            entries.removeValue(forKey: id)
        }
    }

    private func score(_ entry: Entry, at date: Date) -> Double {
        let ageInDays = max(
            0,
            date.timeIntervalSince(entry.lastUsed) / Self.secondsPerDay
        )
        return Double(entry.hits) * pow(
            0.5,
            ageInDays / Self.halfLifeInDays
        )
    }

    private static func sanitized(_ loadedEntries: [String: Entry]) -> [String: Entry] {
        loadedEntries.reduce(into: [:]) { result, item in
            guard item.value.hits > 0 else {
                return
            }
            result[item.key] = Entry(
                hits: min(item.value.hits, maximumHits),
                lastUsed: item.value.lastUsed
            )
        }
    }

    struct Entry: Codable, Equatable {
        let hits: Int
        let lastUsed: Date
    }
}
