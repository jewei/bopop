import Foundation

/// Results the user has permanently hidden, keyed by `SearchResult.id`.
///
/// Frecency already sinks things you never pick, but it can only ever bury
/// them — a background helper or a bundled app you will never launch keeps
/// resurfacing whenever its name happens to match. Hiding is the explicit,
/// durable version of that.
@MainActor
public final class VisibilityStore {
    public private(set) var hiddenIDs: Set<String>

    private static let version = 1
    private let storage: Storage
    private let saveIDs: ([String]) throws -> Void

    public convenience init(storage: Storage) {
        self.init(storage: storage) { ids in
            try storage.save(ids, version: VisibilityStore.version, to: storage.hiddenResultsFileURL)
        }
    }

    init(
        storage: Storage,
        saveIDs: @escaping ([String]) throws -> Void
    ) {
        self.storage = storage
        self.saveIDs = saveIDs
        hiddenIDs = Set(
            storage.loadElements(
                String.self,
                expectedVersion: Self.version,
                from: storage.hiddenResultsFileURL
            ) ?? []
        )
    }

    @discardableResult
    public func hide(_ id: String) -> Result<Void, PersistenceFailure> {
        guard !id.isEmpty, hiddenIDs.insert(id).inserted else {
            return .success(())
        }
        let result = persist()
        if case .failure = result {
            hiddenIDs.remove(id)
        }
        return result
    }

    @discardableResult
    public func show(_ id: String) -> Result<Void, PersistenceFailure> {
        guard hiddenIDs.remove(id) != nil else {
            return .success(())
        }
        let result = persist()
        if case .failure = result {
            hiddenIDs.insert(id)
        }
        return result
    }

    public func isHidden(_ id: String) -> Bool {
        hiddenIDs.contains(id)
    }

    /// Sorted so the file has a stable order and diffs cleanly, rather than
    /// reshuffling with `Set`'s iteration order on every write.
    private func persist() -> Result<Void, PersistenceFailure> {
        do {
            try saveIDs(hiddenIDs.sorted())
            return .success(())
        } catch {
            return .failure(PersistenceFailure(error.localizedDescription))
        }
    }
}
