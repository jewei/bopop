import Foundation

public struct AppInfo: Equatable, Sendable {
    public let bundleID: String?
    public let name: String
    public let path: String
    public let keywords: [String]

    public init(
        bundleID: String?,
        name: String,
        path: String,
        keywords: [String]
    ) {
        self.bundleID = bundleID
        self.name = name
        self.path = path
        self.keywords = keywords
    }
}

@MainActor
public final class AppCatalog {
    public static var defaultDirectories: [URL] {
        [
            URL(fileURLWithPath: "/Applications", isDirectory: true),
            // Cryptex-hosted apps (Safari) are invisible to directory
            // enumeration of /Applications — their firmlink is not listed.
            URL(
                fileURLWithPath: "/System/Cryptexes/App/System/Applications",
                isDirectory: true
            ),
            URL(fileURLWithPath: "/System/Applications", isDirectory: true),
            URL(
                fileURLWithPath: "/System/Applications/Utilities",
                isDirectory: true
            ),
            FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Applications", isDirectory: true)
        ]
    }

    /// Apps that live outside every scanned directory but belong in a launcher.
    public static var defaultExtraApplicationPaths: [String] {
        ["/System/Library/CoreServices/Finder.app"]
    }

    public private(set) var apps: [AppInfo] = []

    private typealias Scanner = @Sendable ([URL], [String], MetadataCache) async
        -> (apps: [AppInfo], cache: MetadataCache)

    private let directories: [URL]
    private let extraApplicationPaths: [String]
    private let staleAfter: TimeInterval
    private let scanner: Scanner
    private var lastScan: Date?
    private var metadataCache = MetadataCache()
    private var refreshTask: Task<Bool, Never>?
    private(set) var forcedRefreshGeneration = 0

    public init(
        directories: [URL] = AppCatalog.defaultDirectories,
        extraApplicationPaths: [String] = AppCatalog.defaultExtraApplicationPaths,
        staleAfter: TimeInterval = 300
    ) {
        self.directories = directories
        self.extraApplicationPaths = extraApplicationPaths
        self.staleAfter = staleAfter
        scanner = { directories, extraApplicationPaths, cache in
            await AppCatalog.scan(
                directories: directories,
                extraApplicationPaths: extraApplicationPaths,
                cache: cache
            )
        }
    }

    init(
        directories: [URL],
        extraApplicationPaths: [String],
        staleAfter: TimeInterval = 300,
        scanner: @escaping @Sendable ([URL], [String], MetadataCache) async
            -> (apps: [AppInfo], cache: MetadataCache)
    ) {
        self.directories = directories
        self.extraApplicationPaths = extraApplicationPaths
        self.staleAfter = staleAfter
        self.scanner = scanner
    }

    public func refreshIfStale() {
        let currentDate = Date()
        if let lastScan,
           currentDate.timeIntervalSince(lastScan) < staleAfter {
            return
        }
        guard refreshTask == nil else {
            return
        }

        _ = startRefresh()
    }

    @discardableResult
    public func refreshNow() async -> Bool {
        forcedRefreshGeneration += 1
        return await startRefresh().value
    }

    private func startRefresh() -> Task<Bool, Never> {
        if let refreshTask {
            return refreshTask
        }

        let initialApps = apps
        let directories = directories
        let extraApplicationPaths = extraApplicationPaths
        let scanner = scanner
        let task = Task { [weak self] in
            guard let self else {
                return false
            }
            defer { refreshTask = nil }

            while !Task.isCancelled {
                let forcedGenerationAtStart = forcedRefreshGeneration
                let cacheAtStart = metadataCache
                let scanned = await PerformanceSignposts.catalog.interval(
                    "App Catalog Refresh"
                ) {
                    await scanner(directories, extraApplicationPaths, cacheAtStart)
                }
                guard !Task.isCancelled else {
                    return false
                }
                guard forcedGenerationAtStart == forcedRefreshGeneration else {
                    // Superseded: keep the cache anyway, since it describes
                    // bundles this process has already read either way.
                    metadataCache = scanned.cache
                    continue
                }

                apps = scanned.apps
                metadataCache = scanned.cache
                lastScan = Date()
                return scanned.apps != initialApps
            }
            return false
        }
        refreshTask = task
        return task
    }

    /// Reusable `AppInfo` values keyed by bundle path, valid while that
    /// bundle's `Info.plist` keeps the modification date it was read at.
    ///
    /// Bopop rescans on every palette summon (see `refreshNow`), and measuring
    /// that scan put 9.2 ms of its 13.3 ms in `Bundle`/`Info.plist` reads
    /// against 0.4 ms of directory walking. Almost none of that work is ever
    /// different from last time.
    public struct MetadataCache: Sendable {
        fileprivate var entries: [String: Entry] = [:]

        fileprivate struct Entry: Sendable {
            let modifiedAt: Date
            let app: AppInfo
        }

        public init() {}
    }

    public static func scan(
        directories: [URL],
        extraApplicationPaths: [String] = []
    ) async -> [AppInfo] {
        await scan(
            directories: directories,
            extraApplicationPaths: extraApplicationPaths,
            cache: MetadataCache()
        ).apps
    }

    public static func scan(
        directories: [URL],
        extraApplicationPaths: [String] = [],
        cache: MetadataCache
    ) async -> (apps: [AppInfo], cache: MetadataCache) {
        let fileManager = FileManager.default
        let resourceKeys: [URLResourceKey] = [.isDirectoryKey]
        var appURLs: [URL] = []

        for directory in directories {
            guard !Task.isCancelled else {
                return ([], cache)
            }
            let topLevelEntries = directoryEntries(
                at: directory,
                resourceKeys: resourceKeys,
                using: fileManager
            )
            for entry in topLevelEntries {
                if isApplication(entry) {
                    appURLs.append(entry)
                    continue
                }
                guard isDirectory(entry, resourceKeys: resourceKeys) else {
                    continue
                }
                let nestedEntries = directoryEntries(
                    at: entry,
                    resourceKeys: resourceKeys,
                    using: fileManager
                )
                appURLs.append(contentsOf: nestedEntries.filter(isApplication))
            }
        }

        for extraPath in extraApplicationPaths
        where fileManager.fileExists(atPath: extraPath) {
            appURLs.append(URL(fileURLWithPath: extraPath, isDirectory: true))
        }

        var bundleIDs = Set<String>()
        var paths = Set<String>()
        var apps: [AppInfo] = []
        // Rebuilt from this pass rather than mutated, so an uninstalled app
        // falls out instead of accumulating for the life of the process.
        var freshCache = MetadataCache()

        for appURL in appURLs {
            let app: AppInfo
            let modifiedAt = infoPlistModificationDate(for: appURL, using: fileManager)
            if let modifiedAt,
               let cached = cache.entries[appURL.path],
               cached.modifiedAt == modifiedAt {
                app = cached.app
            } else {
                app = appInfo(at: appURL, using: fileManager)
            }
            // A bundle whose date could not be read is re-read every scan
            // rather than cached against a date that cannot be compared.
            if let modifiedAt {
                freshCache.entries[appURL.path] = MetadataCache.Entry(
                    modifiedAt: modifiedAt,
                    app: app
                )
            }
            if let bundleID = app.bundleID {
                guard bundleIDs.insert(bundleID).inserted else {
                    continue
                }
            } else {
                guard paths.insert(app.path).inserted else {
                    continue
                }
            }
            apps.append(app)
        }

        let sorted = apps.sorted { lhs, rhs in
            let nameOrder = lhs.name.localizedStandardCompare(rhs.name)
            if nameOrder != .orderedSame {
                return nameOrder == .orderedAscending
            }
            return lhs.path < rhs.path
        }
        return (sorted, freshCache)
    }

    /// The `Info.plist`'s own date, not the bundle directory's: it is the file
    /// whose contents this cache stands in for, and an in-place edit to it need
    /// not touch the enclosing directory's timestamp. Renaming or moving the
    /// bundle changes the path, which is the cache key.
    private static func infoPlistModificationDate(
        for appURL: URL,
        using fileManager: FileManager
    ) -> Date? {
        let plist = appURL
            .appendingPathComponent("Contents", isDirectory: true)
            .appendingPathComponent("Info.plist")
        return try? plist.resourceValues(forKeys: [.contentModificationDateKey])
            .contentModificationDate
    }

    private static func directoryEntries(
        at directory: URL,
        resourceKeys: [URLResourceKey],
        using fileManager: FileManager
    ) -> [URL] {
        let entries = try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: resourceKeys,
            options: [.skipsHiddenFiles]
        )
        return (entries ?? []).sorted { $0.path < $1.path }
    }

    private static func isApplication(_ url: URL) -> Bool {
        url.pathExtension.caseInsensitiveCompare("app") == .orderedSame
    }

    private static func isDirectory(
        _ url: URL,
        resourceKeys: [URLResourceKey]
    ) -> Bool {
        (try? url.resourceValues(forKeys: Set(resourceKeys)).isDirectory) == true
    }

    private static func appInfo(
        at url: URL,
        using fileManager: FileManager
    ) -> AppInfo {
        let path = url.path
        let displayName = fileManager.displayName(atPath: path)
        let name = displayName.lowercased().hasSuffix(".app")
            ? String(displayName.dropLast(4))
            : displayName
        let bundle = Bundle(url: url)
        let bundleName = bundle?.infoDictionary?["CFBundleName"] as? String
        let keywords: [String]
        if let bundleName,
           !bundleName.isEmpty,
           bundleName.caseInsensitiveCompare(name) != .orderedSame {
            keywords = [bundleName]
        } else {
            keywords = []
        }

        return AppInfo(
            bundleID: bundle?.bundleIdentifier,
            name: name,
            path: path,
            keywords: keywords
        )
    }
}

public final class AppsProvider: ResultProvider {
    public let id: ProviderID = .apps

    private let catalog: AppCatalog
    private let frecencyFor: BatchFrecencyLookup
    /// Bundle ids of apps that can be quit right now. Injected because
    /// `NSRunningApplication` is AppKit and this target is UI-framework independent;
    /// the app target filters out Bopop itself and Finder before this sees it.
    /// Defaults to empty so the Quit row simply never appears if unwired.
    private let runningBundleIDs: @Sendable () async -> Set<String>
    /// `SearchResult.id`s the user has hidden. Same injection shape and same
    /// safe default: unwired means nothing is hidden.
    private let hiddenIDs: @Sendable () async -> Set<String>

    public init(
        catalog: AppCatalog,
        frecencyFor: @escaping BatchFrecencyLookup,
        runningBundleIDs: @escaping @Sendable () async -> Set<String> = { [] },
        hiddenIDs: @escaping @Sendable () async -> Set<String> = { [] }
    ) {
        self.catalog = catalog
        self.frecencyFor = frecencyFor
        self.runningBundleIDs = runningBundleIDs
        self.hiddenIDs = hiddenIDs
    }

    public func results(for query: ParsedQuery) async throws -> [SearchResult] {
        guard query.mode == .general || query.mode == .apps else {
            return []
        }

        // AppCatalog is MainActor-isolated and its `apps` array is refreshed
        // from a background Task — snapshot it instead of touching it directly
        // from this now off-main-actor body.
        let catalogApps = await MainActor.run { catalog.apps }
        // Filtered before scoring and matching: a hidden app should cost
        // nothing downstream, and `sortHint` should number what's visible.
        let hidden = await hiddenIDs()
        let indexedApps = catalogApps
            .map { (app: $0, id: resultID(for: $0)) }
            .filter { !hidden.contains($0.id) }
            .enumerated()
            .map { index, entry in
                IndexedApp(app: entry.app, id: entry.id, sortHint: index)
            }
        let selectedApps: [IndexedApp]
        if query.term.isEmpty {
            // Scores for the whole catalog are snapshotted in a single
            // MainActor hop (see BatchFrecencyLookup) instead of one hop
            // per app.
            let scores = await frecencyFor(indexedApps.map(\.id))
            let scoredApps = indexedApps.compactMap { indexedApp -> ScoredApp? in
                let frecency = scores[indexedApp.id] ?? 0
                guard frecency > 0 else {
                    return nil
                }
                return ScoredApp(indexedApp: indexedApp, frecency: frecency)
            }
            selectedApps = scoredApps.sorted { lhs, rhs in
                if lhs.frecency != rhs.frecency {
                    return lhs.frecency > rhs.frecency
                }
                let nameOrder = lhs.indexedApp.app.name.localizedStandardCompare(
                    rhs.indexedApp.app.name
                )
                if nameOrder != .orderedSame {
                    return nameOrder == .orderedAscending
                }
                return lhs.indexedApp.id < rhs.indexedApp.id
            }.prefix(6).map(\.indexedApp)
        } else {
            // Pre-filter to entries Ranker would keep anyway (tier != .none
            // against name+keywords) before mapping — this also means the
            // tilde-abbreviated subtitle below (an NSString bridge + path
            // walk) is only computed for survivors, not the whole catalog.
            let foldedTerm = Ranker.foldedQuery(query.term)
            selectedApps = indexedApps.filter { indexedApp in
                matchesTier(foldedTerm: foldedTerm, app: indexedApp.app)
            }
        }

        // Only asked for once the survivors are known, and only when there are
        // any — an empty result set shouldn't pay for a running-apps snapshot.
        let running = selectedApps.isEmpty ? [] : await runningBundleIDs()

        return selectedApps.map { indexedApp in
            let app = indexedApp.app
            var secondaryActions: [ResultAction] = [
                .copyText(app.path),
                .revealFile(app.path)
            ]
            if let bundleID = app.bundleID, running.contains(bundleID) {
                secondaryActions.append(.quitApp(bundleID))
            }
            secondaryActions.append(.hideResult(indexedApp.id))
            return SearchResult(
                id: indexedApp.id,
                providerID: .apps,
                title: app.name,
                subtitle: (app.path as NSString).abbreviatingWithTildeInPath,
                icon: .appBundle(app.path),
                keywords: app.keywords,
                badge: "Apps",
                action: .openApp(app.path),
                secondaryActions: secondaryActions,
                sortHint: indexedApp.sortHint
            )
        }
    }

    private func resultID(for app: AppInfo) -> String {
        "app:\(app.bundleID ?? app.path)"
    }

    private func matchesTier(foldedTerm: String, app: AppInfo) -> Bool {
        ([app.name] + app.keywords).contains {
            Ranker.tier(foldedQuery: foldedTerm, candidate: $0) != .none
        }
    }

    private struct IndexedApp {
        let app: AppInfo
        let id: String
        let sortHint: Int
    }

    private struct ScoredApp {
        let indexedApp: IndexedApp
        let frecency: Double
    }
}
