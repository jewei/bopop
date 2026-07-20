import Foundation
import UniformTypeIdentifiers

final class SingleResume {
    private var resumed = false

    func claim() -> Bool {
        guard !resumed else {
            return false
        }
        resumed = true
        return true
    }
}

public final class FileSearcher {
    public struct Item: Equatable, Sendable {
        public let path: String
        public let displayName: String
        public let contentTypeDescription: String?
        public let modifiedAt: Date?

        public init(
            path: String,
            displayName: String,
            contentTypeDescription: String?,
            modifiedAt: Date?
        ) {
            self.path = path
            self.displayName = displayName
            self.contentTypeDescription = contentTypeDescription
            self.modifiedAt = modifiedAt
        }
    }

    internal private(set) var didBuildQuery = false
    internal private(set) var lastSearchScopes: [Any] = []

    private let maxResults: Int
    private let scopeProvider: @Sendable () -> [String]
    private var active: ActiveSearch?
    private var nextSearchID = 0

    public init(
        maxResults: Int = 40,
        scopeProvider: @escaping @Sendable () -> [String] = { [] }
    ) {
        self.maxResults = max(0, maxResults)
        self.scopeProvider = scopeProvider
    }

    /// Resolves user-chosen folder paths into NSMetadataQuery scope entries.
    /// Paths that no longer exist are skipped (not auto-pruned from
    /// storage — the drive may be temporarily unmounted). An empty list, or
    /// a list where every path is missing, falls back to the whole-home
    /// scope, matching the empty-list default.
    internal static func resolveScopes(
        paths: [String],
        fileManager: FileManager = .default
    ) -> [Any] {
        let existingPaths = paths.filter { fileManager.fileExists(atPath: $0) }
        guard !existingPaths.isEmpty else {
            return [NSMetadataQueryUserHomeScope]
        }
        return existingPaths.map { URL(fileURLWithPath: $0) }
    }

    public func search(term: String) async -> [Item] {
        guard !term.isEmpty else {
            return []
        }

        return await withTaskCancellationHandler(
            operation: {
                await withCheckedContinuation { continuation in
                    cancelActive()
                    guard !Task.isCancelled else {
                        continuation.resume(returning: [])
                        return
                    }

                    didBuildQuery = true
                    let scopes = Self.resolveScopes(paths: scopeProvider())
                    lastSearchScopes = scopes
                    let query = NSMetadataQuery()
                    query.predicate = NSPredicate(
                        format: "%K CONTAINS[cd] %@",
                        NSMetadataItemFSNameKey,
                        term
                    )
                    query.searchScopes = scopes
                    query.sortDescriptors = [
                        NSSortDescriptor(
                            key: NSMetadataItemFSContentChangeDateKey,
                            ascending: false
                        )
                    ]

                    nextSearchID += 1
                    let searchID = nextSearchID
                    let observerToken = NotificationCenter.default.addObserver(
                        forName: .NSMetadataQueryDidFinishGathering,
                        object: query,
                        queue: .main
                    ) { [weak self] _ in
                        MainActor.assumeIsolated {
                            self?.finishGathering(searchID: searchID)
                        }
                    }
                    active = ActiveSearch(
                        id: searchID,
                        query: query,
                        observerToken: observerToken,
                        continuation: continuation,
                        resumeGuard: SingleResume()
                    )
                    query.start()
                }
            },
            onCancel: {
                Task { @MainActor in
                    self.cancelActive()
                }
            }
        )
    }

    private func finishGathering(searchID: Int) {
        guard let active, active.id == searchID,
              active.resumeGuard.claim() else {
            return
        }

        let query = active.query
        query.disableUpdates()
        let resultCount = min(query.resultCount, maxResults)
        var items: [Item] = []
        items.reserveCapacity(resultCount)
        for index in 0..<resultCount {
            guard let metadataItem = query.result(at: index) as? NSMetadataItem,
                  let path = metadataItem.value(
                    forAttribute: NSMetadataItemPathKey
                  ) as? String else {
                continue
            }
            let displayName = metadataItem.value(
                forAttribute: NSMetadataItemDisplayNameKey
            ) as? String ?? (path as NSString).lastPathComponent
            let contentType = metadataItem.value(
                forAttribute: NSMetadataItemContentTypeKey
            ) as? String
            let contentTypeDescription = contentType.flatMap {
                UTType($0)?.localizedDescription
            }
            let modifiedAt = metadataItem.value(
                forAttribute: NSMetadataItemFSContentChangeDateKey
            ) as? Date
            items.append(
                Item(
                    path: path,
                    displayName: displayName,
                    contentTypeDescription: contentTypeDescription,
                    modifiedAt: modifiedAt
                )
            )
        }

        query.stop()
        NotificationCenter.default.removeObserver(active.observerToken)
        self.active = nil
        active.continuation.resume(returning: items)
    }

    private func cancelActive() {
        guard let active, active.resumeGuard.claim() else {
            return
        }

        active.query.stop()
        NotificationCenter.default.removeObserver(active.observerToken)
        self.active = nil
        active.continuation.resume(returning: [])
    }

    private struct ActiveSearch {
        let id: Int
        let query: NSMetadataQuery
        let observerToken: NSObjectProtocol
        let continuation: CheckedContinuation<[Item], Never>
        let resumeGuard: SingleResume
    }
}

public final class FileSearchProvider: ResultProvider {
    public let id: ProviderID = .files

    private let searchImpl: @MainActor @Sendable (String) async -> [FileSearcher.Item]

    public init(searcher: FileSearcher) {
        searchImpl = { term in
            await searcher.search(term: term)
        }
    }

    init(
        searchImpl: @escaping @MainActor @Sendable (String) async -> [FileSearcher.Item]
    ) {
        self.searchImpl = searchImpl
    }

    public func results(for query: ParsedQuery) async throws -> [SearchResult] {
        guard query.mode == .fileSearch, !query.term.isEmpty else { return [] }

        let items = await searchImpl(query.term)
        guard !Task.isCancelled else {
            return []
        }

        return items.enumerated().map { index, item in
            let parentDirectory = (item.path as NSString).deletingLastPathComponent
            let abbreviatedParent = (parentDirectory as NSString)
                .abbreviatingWithTildeInPath
            let kind = item.contentTypeDescription ?? "File"
            return SearchResult(
                id: "file:\(item.path)",
                providerID: .files,
                title: item.displayName,
                subtitle: "\(abbreviatedParent) · \(kind)",
                icon: .file(item.path),
                keywords: [],
                action: .openFile(item.path),
                secondaryActions: [.copyText(item.path), .revealFile(item.path)],
                sortHint: index
            )
        }
    }
}
