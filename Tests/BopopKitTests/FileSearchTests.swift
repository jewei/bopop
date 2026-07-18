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
func singleResumeCanOnlyBeClaimedOnce() {
    let resumeGuard = SingleResume()

    #expect(resumeGuard.claim())
    #expect(!resumeGuard.claim())
}

@MainActor
@Test
func singleResumeAllowsOneClaimAcrossTasks() async {
    let resumeGuard = SingleResume()

    let claims = await withTaskGroup(
        of: Bool.self,
        returning: [Bool].self
    ) { group in
        for _ in 0..<2 {
            group.addTask {
                await resumeGuard.claim()
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
    #expect(results.map(\.keywords) == [[], []])
    #expect(results.map(\.action) == [.openFile(firstPath), .openFile(secondPath)])
    #expect(results.map(\.secondaryActions) == [
        [.copyText(firstPath)],
        [.copyText(secondPath)]
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
