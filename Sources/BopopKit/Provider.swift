import Foundation
import os

public protocol ResultProvider: Sendable {
    var id: ProviderID { get }
    nonisolated func results(for query: ParsedQuery) async throws -> [SearchResult]
}

/// A batched frecency lookup: given the full list of ids a provider is about
/// to score, returns every score in a single call. Callers whose backing
/// store is MainActor-isolated (e.g. UsageStore) can then take ONE
/// `MainActor.run` hop per `results(for:)` invocation instead of one hop per
/// id — the difference between a single actor round-trip and hundreds of
/// them on an empty-term catalog browse.
public typealias BatchFrecencyLookup = @Sendable ([String]) async -> [String: Double]

/// Foundation formatters are not thread-safe, and some (e.g.
/// RelativeDateTimeFormatter) explicitly opt out of Sendable entirely, so a
/// plain `OSAllocatedUnfairLock<Formatter>` won't compile for them (its usual
/// initializer requires `Formatter: Sendable`). `uncheckedState` exists for
/// exactly this case: the formatter itself is non-Sendable, but every access
/// to it is forced through the lock's `withLock`, which is the same
/// serialization guarantee Sendable would provide — so bypassing the
/// compile-time check here is sound, and `OSAllocatedUnfairLock` remains
/// unconditionally `Sendable` regardless of what it locks.
nonisolated final class FormatterBox<Formatter>: Sendable {
    private let lock: OSAllocatedUnfairLock<Formatter>

    init(_ formatter: Formatter) {
        lock = OSAllocatedUnfairLock(uncheckedState: formatter)
    }

    func withLock<T: Sendable>(_ body: @Sendable (inout Formatter) -> T) -> T {
        lock.withLock(body)
    }
}
