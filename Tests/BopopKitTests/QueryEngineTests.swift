import Foundation
import Testing
@testable import BopopKit

@MainActor
@Test
func queryEngineDiscardsStaleGeneration() async {
    let gate = Gate()
    let provider = FakeProvider(id: .apps) { query in
        if query.term == "first" {
            await gate.wait()
        }
        return [engineResult(id: "app:\(query.term)", title: query.term)]
    }
    let engine = QueryEngine(providers: [.general: [provider]], debounce: [:])
    let recorder = UpdateRecorder()
    engine.onUpdate = recorder.record

    engine.update(raw: "first", stickyMode: .general)
    await gate.waitUntilStarted()
    engine.update(raw: "second", stickyMode: .general)

    let current = await recorder.waitForUpdate { $0.generation == 2 && $0.isFinal }
    #expect(current?.results.map(\.id) == ["app:second"])

    await gate.release()
    try? await Task.sleep(for: .milliseconds(5))
    #expect(recorder.updates.count == 1)
}

@MainActor
@Test
func queryEngineCancellationStopsPublish() async {
    let state = CancellationState()
    let provider = FakeProvider(id: .apps) { _ in
        await state.markStarted()
        do {
            try await Task.sleep(for: .seconds(5))
        } catch is CancellationError {
            await state.markCancelled()
            throw CancellationError()
        }
        return [engineResult(id: "app:late", title: "Late")]
    }
    let engine = QueryEngine(providers: [.general: [provider]], debounce: [:])
    let recorder = UpdateRecorder()
    engine.onUpdate = recorder.record

    engine.update(raw: "late", stickyMode: .general)
    await state.waitUntilStarted()
    engine.cancel()
    await state.waitUntilCancelled()
    try? await Task.sleep(for: .milliseconds(5))

    #expect(recorder.updates.isEmpty)
}

@MainActor
@Test
func queryEngineIsolatesThrowingProvider() async {
    let bad = FakeProvider(id: .files) { _ in
        throw FakeError.failed
    }
    let good = FakeProvider(id: .apps) { _ in
        [engineResult(id: "app:good", title: "Good")]
    }
    let engine = QueryEngine(
        providers: [.general: [bad, good]],
        debounce: [:]
    )
    let recorder = UpdateRecorder()
    engine.onUpdate = recorder.record

    engine.update(raw: "good", stickyMode: .general)
    let final = await recorder.waitForUpdate(matching: \.isFinal)

    #expect(final?.results.map(\.id) == ["app:good"])
}

@MainActor
@Test
func queryEnginePublishesIncrementally() async {
    let slowGate = Gate()
    let fast = FakeProvider(id: .commands) { _ in
        [engineResult(id: "cmd:fast", providerID: .commands, title: "Fast")]
    }
    let slow = FakeProvider(id: .apps) { _ in
        await slowGate.wait()
        return [engineResult(id: "app:slow", title: "Slow")]
    }
    let engine = QueryEngine(
        providers: [.general: [fast, slow]],
        debounce: [:]
    )
    let recorder = UpdateRecorder()
    engine.onUpdate = recorder.record

    engine.update(raw: "", stickyMode: .general)
    await slowGate.waitUntilStarted()
    let first = await recorder.waitForUpdate { !$0.isFinal }
    #expect(first?.results.map(\.id) == ["cmd:fast"])

    await slowGate.release()
    let final = await recorder.waitForUpdate(matching: \.isFinal)
    #expect(Set(final?.results.map(\.id) ?? []) == ["cmd:fast", "app:slow"])
}

@MainActor
@Test
func queryEngineDebounceCancelsEarlierSleep() async {
    let calls = QueryCallRecorder()
    let provider = FakeProvider(id: .files) { query in
        await calls.record(query.term)
        return [engineResult(id: "file:\(query.term)", providerID: .files, title: query.term)]
    }
    let engine = QueryEngine(
        providers: [.fileSearch: [provider]],
        debounce: [.fileSearch: .milliseconds(10)]
    )
    let recorder = UpdateRecorder()
    engine.onUpdate = recorder.record

    engine.update(raw: "first", stickyMode: .fileSearch)
    engine.update(raw: "second", stickyMode: .fileSearch)

    let final = await recorder.waitForUpdate(matching: \.isFinal)
    #expect(final?.generation == 2)
    #expect(final?.results.map(\.id) == ["file:second"])
    #expect(await calls.values == ["second"])
}

@MainActor
@Test
func queryEngineRunsProvidersConcurrently() async {
    // Two providers that are each truly nonisolated (unlike FakeProvider,
    // which stays MainActor-isolated and hops for every call) sleeping
    // ~400ms apiece. Before task 8, every provider body ran on the main
    // actor regardless of the task-group fan-out, so this would have taken
    // the SUM of both sleeps (800ms+). With real off-actor concurrency it
    // should complete in close to one sleep's worth of wall time. The
    // margin here is deliberately generous (700ms cutoff, not ~450ms) —
    // under `swift test`'s default full-suite parallelism this test's own
    // wall clock is subject to real scheduling jitter from ~200 other
    // concurrently-running tests, and a tight cutoff was observed to flake.
    let providerA = NonisolatedFakeProvider(id: .apps) { query in
        try await Task.sleep(for: .milliseconds(400))
        return [engineResult(id: "a:\(query.term)", title: query.term)]
    }
    let providerB = NonisolatedFakeProvider(id: .files) { query in
        try await Task.sleep(for: .milliseconds(400))
        return [engineResult(id: "b:\(query.term)", providerID: .files, title: query.term)]
    }
    let engine = QueryEngine(
        providers: [.general: [providerA, providerB]],
        debounce: [:]
    )
    let recorder = UpdateRecorder()
    engine.onUpdate = recorder.record

    let clock = ContinuousClock()
    let start = clock.now
    engine.update(raw: "go", stickyMode: .general)
    let final = await recorder.waitForUpdate(matching: \.isFinal)
    let elapsed = clock.now - start

    #expect(Set(final?.results.map(\.id) ?? []) == ["a:go", "b:go"])
    #expect(elapsed < .milliseconds(700))
}

@MainActor
private final class FakeProvider: ResultProvider {
    let id: ProviderID
    private let operation: @MainActor @Sendable (ParsedQuery) async throws -> [SearchResult]

    init(
        id: ProviderID,
        operation: @escaping @MainActor @Sendable (ParsedQuery) async throws -> [SearchResult]
    ) {
        self.id = id
        self.operation = operation
    }

    func results(for query: ParsedQuery) async throws -> [SearchResult] {
        try await operation(query)
    }
}

/// Unlike FakeProvider (deliberately @MainActor, matching how most real
/// providers still hop back to MainActor for their actual work), this one is
/// truly nonisolated end to end — both stored properties are immutable and
/// Sendable, so no `@unchecked` is needed — letting queryEngineRunsProvidersConcurrently
/// prove QueryEngine's task-group fan-out gives genuine overlap and isn't
/// just serializing through the main actor.
private nonisolated final class NonisolatedFakeProvider: ResultProvider {
    let id: ProviderID
    private let operation: @Sendable (ParsedQuery) async throws -> [SearchResult]

    init(
        id: ProviderID,
        operation: @escaping @Sendable (ParsedQuery) async throws -> [SearchResult]
    ) {
        self.id = id
        self.operation = operation
    }

    func results(for query: ParsedQuery) async throws -> [SearchResult] {
        try await operation(query)
    }
}

@MainActor
private final class UpdateRecorder {
    private(set) var updates: [QueryEngine.Update] = []

    func record(_ update: QueryEngine.Update) {
        updates.append(update)
    }

    func waitForUpdate(
        timeout: Duration = .seconds(1),
        matching predicate: (QueryEngine.Update) -> Bool
    ) async -> QueryEngine.Update? {
        let clock = ContinuousClock()
        let deadline = clock.now + timeout
        while clock.now < deadline {
            if let update = updates.first(where: predicate) {
                return update
            }
            try? await Task.sleep(for: .milliseconds(1))
        }
        return updates.first(where: predicate)
    }
}

private actor Gate {
    private var started = false
    private var releaseContinuation: CheckedContinuation<Void, Never>?
    private var startContinuations: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        started = true
        let continuations = startContinuations
        startContinuations.removeAll()
        continuations.forEach { $0.resume() }
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

private actor CancellationState {
    private var started = false
    private var cancelled = false
    private var startedContinuations: [CheckedContinuation<Void, Never>] = []
    private var cancelledContinuations: [CheckedContinuation<Void, Never>] = []

    func markStarted() {
        started = true
        startedContinuations.forEach { $0.resume() }
        startedContinuations.removeAll()
    }

    func markCancelled() {
        cancelled = true
        cancelledContinuations.forEach { $0.resume() }
        cancelledContinuations.removeAll()
    }

    func waitUntilStarted() async {
        if started {
            return
        }
        await withCheckedContinuation { continuation in
            startedContinuations.append(continuation)
        }
    }

    func waitUntilCancelled() async {
        if cancelled {
            return
        }
        await withCheckedContinuation { continuation in
            cancelledContinuations.append(continuation)
        }
    }
}

private actor QueryCallRecorder {
    private(set) var values: [String] = []

    func record(_ value: String) {
        values.append(value)
    }
}

private enum FakeError: Error {
    case failed
}

private nonisolated func engineResult(
    id: String,
    providerID: ProviderID = .apps,
    title: String
) -> SearchResult {
    SearchResult(
        id: id,
        providerID: providerID,
        title: title,
        action: .copyText(title),
        sortHint: 0
    )
}
