import Foundation

public nonisolated struct AppInfo: Equatable, Sendable {
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

public final class AppCatalog {
    public static var defaultDirectories: [URL] {
        [
            URL(fileURLWithPath: "/Applications", isDirectory: true),
            URL(fileURLWithPath: "/System/Applications", isDirectory: true),
            URL(
                fileURLWithPath: "/System/Applications/Utilities",
                isDirectory: true
            ),
            FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Applications", isDirectory: true)
        ]
    }

    public private(set) var apps: [AppInfo] = []

    private let directories: [URL]
    private let staleAfter: TimeInterval
    private var lastScan: Date?
    private var refreshTask: Task<Void, Never>?

    public init(
        directories: [URL] = AppCatalog.defaultDirectories,
        staleAfter: TimeInterval = 300
    ) {
        self.directories = directories
        self.staleAfter = staleAfter
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

        let directories = directories
        refreshTask = Task { [weak self] in
            let scannedApps = await Self.scan(directories: directories)
            guard let self, !Task.isCancelled else {
                return
            }
            apps = scannedApps
            lastScan = Date()
            refreshTask = nil
        }
    }

    public func refreshNow() async {
        refreshTask?.cancel()
        refreshTask = nil
        apps = await Self.scan(directories: directories)
        lastScan = Date()
    }

    public static nonisolated func scan(directories: [URL]) async -> [AppInfo] {
        let fileManager = FileManager.default
        let resourceKeys: [URLResourceKey] = [.isDirectoryKey]
        var appURLs: [URL] = []

        for directory in directories {
            guard !Task.isCancelled else {
                return []
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

        var bundleIDs = Set<String>()
        var paths = Set<String>()
        var apps: [AppInfo] = []

        for appURL in appURLs {
            let app = appInfo(at: appURL, using: fileManager)
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

        return apps.sorted { lhs, rhs in
            let nameOrder = lhs.name.localizedStandardCompare(rhs.name)
            if nameOrder != .orderedSame {
                return nameOrder == .orderedAscending
            }
            return lhs.path < rhs.path
        }
    }

    private static nonisolated func directoryEntries(
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

    private static nonisolated func isApplication(_ url: URL) -> Bool {
        url.pathExtension.caseInsensitiveCompare("app") == .orderedSame
    }

    private static nonisolated func isDirectory(
        _ url: URL,
        resourceKeys: [URLResourceKey]
    ) -> Bool {
        (try? url.resourceValues(forKeys: Set(resourceKeys)).isDirectory) == true
    }

    private static nonisolated func appInfo(
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
    private let frecencyFor: (String) -> Double

    public init(
        catalog: AppCatalog,
        frecencyFor: @escaping (String) -> Double
    ) {
        self.catalog = catalog
        self.frecencyFor = frecencyFor
    }

    public func results(for query: ParsedQuery) async throws -> [SearchResult] {
        guard query.mode == .general else {
            return []
        }

        let indexedApps = catalog.apps.enumerated().map { index, app in
            IndexedApp(
                app: app,
                id: resultID(for: app),
                sortHint: index
            )
        }
        let selectedApps: [IndexedApp]
        if query.term.isEmpty {
            let scoredApps: [ScoredApp] = indexedApps.compactMap { indexedApp in
                let frecency = frecencyFor(indexedApp.id)
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
            selectedApps = indexedApps
        }

        return selectedApps.map { indexedApp in
            let app = indexedApp.app
            return SearchResult(
                id: indexedApp.id,
                providerID: .apps,
                title: app.name,
                subtitle: (app.path as NSString).abbreviatingWithTildeInPath,
                icon: .appBundle(app.path),
                keywords: app.keywords,
                action: .openApp(app.path),
                secondaryActions: [.copyText(app.path)],
                sortHint: indexedApp.sortHint
            )
        }
    }

    private func resultID(for app: AppInfo) -> String {
        "app:\(app.bundleID ?? app.path)"
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
