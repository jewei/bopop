import Foundation
import Testing
@testable import BopopKit

// Live Spotlight smoke test — machine-dependent, so opt-in only:
//   BOPOP_LIVE_SPOTLIGHT=1 swift test --filter liveSpotlightSearchReturnsResults
private let liveEnabled = ProcessInfo.processInfo.environment["BOPOP_LIVE_SPOTLIGHT"] == "1"

@Test(.enabled(if: liveEnabled))
@MainActor
func liveSpotlightSearchReturnsResults() async {
    let searcher = FileSearcher(maxResults: 10)
    let items = await searcher.search(term: "Package.swift")
    #expect(!items.isEmpty)
    #expect(items.allSatisfy { !$0.path.isEmpty })
}

@Test(.enabled(if: liveEnabled))
@MainActor
func liveSearchCancellationResumesEmpty() async {
    let searcher = FileSearcher(maxResults: 10)
    let task = Task { await searcher.search(term: "a") }
    task.cancel()
    let items = await task.value
    #expect(items.isEmpty)
}
