import Testing
@testable import BopopKit

private struct SignpostProbeError: Error, Equatable {}

@Test
func performanceSignposterReturnsSynchronousResult() throws {
    let signposter = PerformanceSignposter.disabled
    var calls = 0

    let result = signposter.interval("Test Sync") {
        calls += 1
        return 42
    }

    #expect(result == 42)
    #expect(calls == 1)
}

@Test
func performanceSignposterPropagatesSynchronousError() {
    let signposter = PerformanceSignposter.disabled

    #expect(throws: SignpostProbeError.self) {
        try signposter.interval("Test Sync Error") {
            throw SignpostProbeError()
        }
    }
}

@Test
func performanceSignposterReturnsAsynchronousResult() async throws {
    let signposter = PerformanceSignposter.disabled

    let result = await signposter.interval("Test Async") {
        await Task.yield()
        return 84
    }

    #expect(result == 84)
}

@Test
func performanceSignposterPropagatesAsynchronousError() async {
    let signposter = PerformanceSignposter.disabled

    await #expect(throws: SignpostProbeError.self) {
        try await signposter.interval("Test Async Error") {
            await Task.yield()
            throw SignpostProbeError()
        }
    }
}
