import Foundation
import Testing
@testable import BopopKit

@MainActor
@Test
func fileSearchProviderDoesNotBuildQueriesOutsideActiveSearch() async throws {
    let searcher = FileSearcher()
    let provider = FileSearchProvider(searcher: searcher)

    let generalResults = try await provider.results(
        for: ParsedQuery(mode: .general, term: "report")
    )
    let emptyResults = try await provider.results(
        for: ParsedQuery(mode: .fileSearch, term: "")
    )
    let directEmptyResults = await searcher.search(term: "")

    #expect(generalResults.isEmpty)
    #expect(emptyResults.isEmpty)
    #expect(directEmptyResults.isEmpty)
    #expect(!searcher.didBuildQuery)
}

@MainActor
@Test
func resolveScopesFallsBackToHomeWhenPathsEmpty() {
    let scopes = FileSearcher.resolveScopes(paths: [], fileManager: .default)

    #expect(scopes as? [String] == [NSMetadataQueryUserHomeScope])
}

@MainActor
@Test
func resolveScopesFallsBackToHomeWhenAllPathsMissing() {
    let missing = "/nonexistent-\(UUID().uuidString)"

    let scopes = FileSearcher.resolveScopes(paths: [missing], fileManager: .default)

    #expect(scopes as? [String] == [NSMetadataQueryUserHomeScope])
}

@MainActor
@Test
func resolveScopesUsesChosenExistingFolders() {
    let existing = FileManager.default.temporaryDirectory.path

    let scopes = FileSearcher.resolveScopes(paths: [existing], fileManager: .default)

    #expect(scopes as? [URL] == [URL(fileURLWithPath: existing)])
}

@MainActor
@Test
func resolveScopesSkipsMissingPathsAtBuildTimeButKeepsExisting() {
    let existing = FileManager.default.temporaryDirectory.path
    let missing = "/nonexistent-\(UUID().uuidString)"

    let scopes = FileSearcher.resolveScopes(
        paths: [missing, existing],
        fileManager: .default
    )

    #expect(scopes as? [URL] == [URL(fileURLWithPath: existing)])
}

@MainActor
@Test
func fileSearcherReadsScopeProviderPerSearchAndSkipsMissingPaths() async {
    let existing = FileManager.default.temporaryDirectory.path
    let missing = "/nonexistent-\(UUID().uuidString)"
    let searcher = FileSearcher(scopeProvider: { [missing, existing] })

    let task = Task { await searcher.search(term: "test") }
    // scopeProvider is now awaited (it's an async hop to MainActor in the
    // real app), so the scope-resolution/query-build step is no longer
    // guaranteed to land after a fixed number of yields the way a purely
    // synchronous call was — poll instead of assuming a fixed scheduling
    // shape, up to a generous timeout, before falling back to the gathering
    // notification wait.
    // Bounds failure only — the loop exits as soon as the query is built, so
    // the deadline just needs to outlast CI's parallel-load scheduling delays
    // (see UpdateRecorder.waitForUpdate, where 1 s proved too tight).
    let clock = ContinuousClock()
    let deadline = clock.now + .seconds(20)
    while !searcher.didBuildQuery, clock.now < deadline {
        await Task.yield()
    }

    #expect(searcher.didBuildQuery)
    #expect(searcher.lastSearchScopes as? [URL] == [URL(fileURLWithPath: existing)])

    task.cancel()
    _ = await task.value
}

@Test
func singleResumeCanOnlyBeClaimedOnce() {
    let resumeGuard = SingleResume()

    #expect(resumeGuard.claim())
    #expect(!resumeGuard.claim())
}

@Test
func singleResumeAllowsOneClaimAcrossTasks() async {
    let resumeGuard = SingleResume()

    let claims = await withTaskGroup(
        of: Bool.self,
        returning: [Bool].self
    ) { group in
        for _ in 0..<2 {
            group.addTask {
                resumeGuard.claim()
            }
        }
        var values: [Bool] = []
        for await value in group {
            values.append(value)
        }
        return values
    }

    #expect(claims.filter { $0 }.count == 1)
    #expect(claims.filter { !$0 }.count == 1)
}

@MainActor
@Test
func fileSearchProviderMapsItems() async throws {
    let home = FileManager.default.homeDirectoryForCurrentUser.path
    let firstPath = (home as NSString)
        .appendingPathComponent("Documents/Quarterly Report.pdf")
    let secondPath = (home as NSString)
        .appendingPathComponent("Desktop/Notes.txt")
    let modifiedAt = Date(timeIntervalSince1970: 1_000)
    let provider = FileSearchProvider { term in
        #expect(term == "report")
        return [
            FileSearcher.Item(
                path: firstPath,
                displayName: "Quarterly Report.pdf",
                contentTypeDescription: "PDF document",
                modifiedAt: modifiedAt
            ),
            FileSearcher.Item(
                path: secondPath,
                displayName: "Notes.txt",
                contentTypeDescription: nil,
                modifiedAt: nil
            )
        ]
    }

    let results = try await provider.results(
        for: ParsedQuery(mode: .fileSearch, term: "report")
    )

    #expect(results.map(\.id) == ["file:\(firstPath)", "file:\(secondPath)"])
    #expect(results.map(\.title) == ["Quarterly Report.pdf", "Notes.txt"])
    #expect(results.map(\.subtitle) == [
        "~/Documents · PDF document",
        "~/Desktop · File"
    ])
    #expect(results.map(\.icon) == [.file(firstPath), .file(secondPath)])
    #expect(results.map(\.badge) == ["Files", "Files"])
    #expect(results.map(\.keywords) == [[], []])
    #expect(results.map(\.action) == [.openFile(firstPath), .openFile(secondPath)])
    #expect(results.map(\.secondaryActions) == [
        [.copyText(firstPath), .revealFile(firstPath)],
        [.copyText(secondPath), .revealFile(secondPath)]
    ])
    #expect(results.map(\.sortHint) == [0, 1])
}

@MainActor
@Test
func fileSearchProviderDropsItemsWhenCancelledAfterSearch() async throws {
    let gate = FileSearchGate()
    let provider = FileSearchProvider { _ in
        await gate.wait()
        return [
            FileSearcher.Item(
                path: "/tmp/late.txt",
                displayName: "late.txt",
                contentTypeDescription: nil,
                modifiedAt: nil
            )
        ]
    }
    let task = Task {
        try await provider.results(
            for: ParsedQuery(mode: .fileSearch, term: "late")
        )
    }

    await gate.waitUntilStarted()
    task.cancel()
    await gate.release()

    #expect(try await task.value == [])
}

private actor FileSearchGate {
    private var started = false
    private var releaseContinuation: CheckedContinuation<Void, Never>?
    private var startContinuations: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        started = true
        startContinuations.forEach { $0.resume() }
        startContinuations.removeAll()
        await withCheckedContinuation { continuation in
            releaseContinuation = continuation
        }
    }

    func waitUntilStarted() async {
        if started {
            return
        }
        await withCheckedContinuation { continuation in
            startContinuations.append(continuation)
        }
    }

    func release() {
        releaseContinuation?.resume()
        releaseContinuation = nil
    }
}

@MainActor
@Test
func fileSearchRanksOlderExactMatchBeforeLimitingResults() async throws {
    let names = (0..<80).map { "report.pdf revision \($0)" } + ["report.pdf"]
    let query = FixtureMetadataQuery(names: names)
    let searcher = FileSearcher(queryFactory: { query })
    let provider = FileSearchProvider(searcher: searcher)
    let engine = QueryEngine(providers: [.fileSearch: [provider]], debounce: [:])
    var final: QueryEngine.Update?
    engine.onUpdate = { if $0.isFinal { final = $0 } }

    engine.update(query: ParsedQuery(mode: .fileSearch, term: "report.pdf"))
    let clock = ContinuousClock()
    let deadline = clock.now + .seconds(20)
    while !searcher.didBuildQuery, clock.now < deadline {
        await Task.yield()
    }
    try #require(searcher.didBuildQuery)
    NotificationCenter.default.post(name: .NSMetadataQueryDidFinishGathering, object: query)
    while final == nil, clock.now < deadline {
        await Task.yield()
    }

    let results = try #require(final).results
    #expect(results.count == 40)
    #expect(results.first?.title == "report.pdf")
    // Equal-tier matches keep Spotlight's recency order, not alphabetical order.
    #expect(results.dropFirst().map(\.title) == Array(names.prefix(39)))
}

@MainActor
@Test(arguments: [0, 3, 200])
func fileSearchBoundsCandidateConversion(limit: Int) async throws {
    let query = FixtureMetadataQuery(names: (0..<1_000).map { "report \($0)" })
    let searcher = FileSearcher(candidateLimit: limit, queryFactory: { query })
    let task = Task { await searcher.search(term: "report") }
    defer { task.cancel() }
    let clock = ContinuousClock()
    let deadline = clock.now + .seconds(20)
    while !searcher.didBuildQuery, clock.now < deadline {
        await Task.yield()
    }
    try #require(searcher.didBuildQuery)
    NotificationCenter.default.post(name: .NSMetadataQueryDidFinishGathering, object: query)

    #expect(await task.value.count == limit)
    #expect(query.readCount == limit)
}

private final class FixtureMetadataQuery: NSMetadataQuery {
    private let items: [FixtureMetadataItem]
    private(set) var readCount = 0

    init(names: [String]) {
        items = names.enumerated().map { FixtureMetadataItem(name: $1, index: $0) }
        super.init()
    }

    override var resultCount: Int { items.count }
    override func start() -> Bool { true }
    override func stop() {}
    override func disableUpdates() {}

    override func result(at index: Int) -> Any {
        readCount += 1
        return items[index]
    }
}

// Optional fixed-data measurement. Spotlight gathering and UI rendering are excluded.
@MainActor
@Test(.enabled(if: ProcessInfo.processInfo.environment["BOPOP_FILE_SEARCH_BENCHMARK"] == "1"))
func fileSearchCandidateProcessingBenchmark() async throws {
    let clock = ContinuousClock()
    let names = (0..<1_000).map { "Document \($0).pdf" }
    for limit in [40, 200, 1_000] {
        for sample in 0..<31 {
            let query = FixtureMetadataQuery(names: names)
            let searcher = FileSearcher(candidateLimit: limit, queryFactory: { query })
            let provider = FileSearchProvider(searcher: searcher)
            let start = clock.now
            let task = Task {
                try await provider.results(for: ParsedQuery(mode: .fileSearch, term: "pdf"))
            }
            defer { task.cancel() }
            let deadline = start + .seconds(20)
            while !searcher.didBuildQuery, clock.now < deadline { await Task.yield() }
            try #require(searcher.didBuildQuery)
            NotificationCenter.default.post(name: .NSMetadataQueryDidFinishGathering, object: query)
            let candidates = try await task.value
            let converted = clock.now
            let ranked = Ranker.rank(
                candidates, query: "pdf", frecencyFor: { _ in 0 },
                providerWeights: Ranker.defaultWeights
            )
            let finished = clock.now
            #expect(ranked.count == limit)

            func milliseconds(_ duration: Duration) -> Double {
                Double(duration.components.seconds) * 1_000
                    + Double(duration.components.attoseconds) / 1e15
            }
            print(
                "FILE_BENCHMARK limit=\(limit) sample=\(sample) "
                    + "convertAndMapMs=\(milliseconds(start.duration(to: converted))) "
                    + "rankMs=\(milliseconds(converted.duration(to: finished)))"
            )
        }
    }
}

private final class FixtureMetadataItem: NSMetadataItem {
    private let name: String
    private let index: Int

    init(name: String, index: Int) {
        self.name = name
        self.index = index
        super.init()
    }

    override func value(forAttribute key: String) -> Any? {
        switch key {
        case NSMetadataItemPathKey: "/fixture/\(index)/\(name)"
        case NSMetadataItemDisplayNameKey: name
        case NSMetadataItemContentTypeKey: "com.adobe.pdf"
        case NSMetadataItemFSContentChangeDateKey: Date(timeIntervalSince1970: Double(10_000 - index))
        default: nil
        }
    }
}
