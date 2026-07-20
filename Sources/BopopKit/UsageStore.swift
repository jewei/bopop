import Foundation

public final class UsageStore {
    private static let version = 1
    private static let maximumHits = 999
    private static let halfLifeInDays = 14.0
    private static let secondsPerDay = 86_400.0

    private let storage: Storage
    private let now: () -> Date
    private let maxEntries: Int
    private var entries: [String: Entry]

    public init(
        storage: Storage,
        now: @escaping () -> Date = Date.init,
        maxEntries: Int = 500
    ) {
        self.storage = storage
        self.now = now
        self.maxEntries = max(0, maxEntries)
        entries = storage.load(
            [String: Entry].self,
            expectedVersion: Self.version,
            from: storage.usageFileURL
        ) ?? [:]
    }

    public func record(_ id: String) {
        let currentDate = now()
        let hits = min((entries[id]?.hits ?? 0) + 1, Self.maximumHits)
        entries[id] = Entry(hits: hits, lastUsed: currentDate)
        evictEntriesIfNeeded(at: currentDate)
        try? storage.save(
            entries,
            version: Self.version,
            to: storage.usageFileURL
        )
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
        let ageInDays = date.timeIntervalSince(entry.lastUsed) / Self.secondsPerDay
        return Double(entry.hits) * pow(
            0.5,
            ageInDays / Self.halfLifeInDays
        )
    }

    private struct Entry: Codable {
        let hits: Int
        let lastUsed: Date
    }
}
