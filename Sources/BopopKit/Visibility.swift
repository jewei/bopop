import Foundation

/// Results the user has permanently hidden, keyed by `SearchResult.id`.
///
/// Frecency already sinks things you never pick, but it can only ever bury
/// them — a background helper or a bundled app you will never launch keeps
/// resurfacing whenever its name happens to match. Hiding is the explicit,
/// durable version of that.
public final class VisibilityStore {
    public private(set) var hiddenIDs: Set<String>

    private static let version = 1
    private let storage: Storage

    public init(storage: Storage) {
        self.storage = storage
        hiddenIDs = Set(
            storage.loadElements(
                String.self,
                expectedVersion: Self.version,
                from: storage.hiddenResultsFileURL
            ) ?? []
        )
    }

    public func hide(_ id: String) {
        guard !id.isEmpty, hiddenIDs.insert(id).inserted else {
            return
        }
        persist()
    }

    public func show(_ id: String) {
        guard hiddenIDs.remove(id) != nil else {
            return
        }
        persist()
    }

    public func isHidden(_ id: String) -> Bool {
        hiddenIDs.contains(id)
    }

    /// Sorted so the file has a stable order and diffs cleanly, rather than
    /// reshuffling with `Set`'s iteration order on every write.
    private func persist() {
        try? storage.save(
            hiddenIDs.sorted(),
            version: Self.version,
            to: storage.hiddenResultsFileURL
        )
    }
}
