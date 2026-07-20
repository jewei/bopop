import Foundation
import Testing
@testable import BopopKit

// MARK: - CurrencyParser

@Test
func currencyParserAcceptsValidExpressions() {
    #expect(CurrencyParser.parse("123myr to usd")
        == CurrencyQuery(amount: 123, from: "MYR", to: "USD"))
    #expect(CurrencyParser.parse("100 usd in myr")
        == CurrencyQuery(amount: 100, from: "USD", to: "MYR"))
    #expect(CurrencyParser.parse("€45 to myr")
        == CurrencyQuery(amount: 45, from: "EUR", to: "MYR"))
    #expect(CurrencyParser.parse("myr 250 to sgd")
        == CurrencyQuery(amount: 250, from: "MYR", to: "SGD"))
    #expect(CurrencyParser.parse("$1,200 to sgd")
        == CurrencyQuery(amount: 1_200, from: "USD", to: "SGD"))
    #expect(CurrencyParser.parse("100 USD TO myr")
        == CurrencyQuery(amount: 100, from: "USD", to: "MYR"))
    #expect(CurrencyParser.parse("100 usd to usd")
        == CurrencyQuery(amount: 100, from: "USD", to: "USD"))
}

@Test
func currencyParserRejectsInvalidExpressions() {
    #expect(CurrencyParser.parse("hello world") == nil)
    #expect(CurrencyParser.parse("123*456") == nil)
    #expect(CurrencyParser.parse("to usd") == nil)
    #expect(CurrencyParser.parse("100 usd to") == nil)
    #expect(CurrencyParser.parse("100 xyz to usd") == nil)
    #expect(CurrencyParser.parse("100 usd to xyz") == nil)
    #expect(CurrencyParser.parse("0 usd to myr") == nil)
    #expect(CurrencyParser.parse("") == nil)
    #expect(CurrencyParser.parse("   ") == nil)
}

// MARK: - CachedRates

@Test
func cachedRatesConvertsAcrossEURBase() throws {
    let rates = CachedRates(
        rates: ["EUR": 1.0, "MYR": 4.0, "USD": 1.0],
        fetchedAt: Date(timeIntervalSince1970: 0)
    )
    let query = CurrencyQuery(amount: 123, from: "MYR", to: "USD")

    let converted = try #require(rates.convert(query))
    #expect(abs(converted - (123 / 4.0 * 1.0)) < 1e-9)
}

@Test
func cachedRatesConvertReturnsNilForUnknownCode() {
    let rates = CachedRates(rates: ["EUR": 1.0], fetchedAt: Date(timeIntervalSince1970: 0))
    let query = CurrencyQuery(amount: 10, from: "MYR", to: "EUR")
    #expect(rates.convert(query) == nil)
}

@Test
func cachedRatesStalenessBoundary() {
    let fetchedAt = Date(timeIntervalSince1970: 0)
    let rates = CachedRates(rates: ["EUR": 1.0], fetchedAt: fetchedAt)

    let almostTwelveHours = fetchedAt.addingTimeInterval(11 * 3_600 + 59 * 60)
    #expect(rates.isStale(now: almostTwelveHours) == false)

    let justOverTwelveHours = fetchedAt.addingTimeInterval(12 * 3_600 + 60)
    #expect(rates.isStale(now: justOverTwelveHours) == true)
}

// MARK: - RateStore

@MainActor
@Test
func rateStoreSavesAndLoadsRoundTrip() throws {
    let fixture = try makeCurrencyStorage()
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    let store = RateStore(storage: fixture.storage)
    let fetchedAt = Date(timeIntervalSince1970: 1_000)

    store.save(rates: ["EUR": 1.0, "USD": 1.08], fetchedAt: fetchedAt)
    let loaded = try #require(store.cached())

    #expect(loaded.rates == ["EUR": 1.0, "USD": 1.08])
    #expect(loaded.fetchedAt == fetchedAt)
}

@MainActor
@Test
func rateStoreReturnsNilWhenAbsent() throws {
    let fixture = try makeCurrencyStorage()
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    let store = RateStore(storage: fixture.storage)

    #expect(store.cached() == nil)
}

@MainActor
@Test
func rateStoreQuarantinesCorruptFile() throws {
    let fixture = try makeCurrencyStorage()
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    try Data("not json".utf8).write(to: fixture.storage.ratesFileURL)
    let store = RateStore(storage: fixture.storage)

    let loaded = store.cached()
    let corruptURL = fixture.storage.ratesFileURL.appendingPathExtension("corrupt")

    #expect(loaded == nil)
    #expect(!FileManager.default.fileExists(atPath: fixture.storage.ratesFileURL.path))
    #expect(FileManager.default.fileExists(atPath: corruptURL.path))
}

// MARK: - CurrencyProvider

@MainActor
@Test
func currencyProviderIgnoresNonMatchingTerms() async throws {
    let fixture = try makeCurrencyStorage()
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    let store = RateStore(storage: fixture.storage)
    let fetcher = MockRateFetcher(result: .success(["EUR": 1.0, "USD": 1.08]))
    let provider = CurrencyProvider(store: store, fetcher: fetcher)

    let results = try await provider.results(
        for: ParsedQuery(mode: .general, term: "hello world")
    )
    let wrongMode = try await provider.results(
        for: ParsedQuery(mode: .fileSearch, term: "100 usd to myr")
    )

    #expect(results.isEmpty)
    #expect(wrongMode.isEmpty)
    #expect(await fetcher.callCount == 0)
}

@MainActor
@Test
func currencyProviderFreshCacheAnswersWithoutFetching() async throws {
    let fixture = try makeCurrencyStorage()
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    let store = RateStore(storage: fixture.storage)
    let fixedNow = Date(timeIntervalSince1970: 100_000)
    store.save(
        rates: ["EUR": 1.0, "MYR": 4.0, "USD": 1.0],
        fetchedAt: fixedNow.addingTimeInterval(-60)
    )
    let fetcher = MockRateFetcher(result: .success([:]))
    let provider = CurrencyProvider(store: store, fetcher: fetcher, now: { fixedNow })

    let results = try await provider.results(
        for: ParsedQuery(mode: .general, term: "123myr to usd")
    )

    #expect(await fetcher.callCount == 0)
    let hero = try #require(results.first?.hero)
    #expect(hero.left == "123 MYR")
    #expect(hero.leftBadge == "Malaysian Ringgit")
    #expect(hero.right == "$30.75")
    #expect(hero.rightBadge == "US Dollar")
    #expect(hero.note == nil)
    #expect(results.first?.action == .copyText("30.75"))
    #expect(results.first?.keywords == ["123myr to usd"])
}

@MainActor
@Test
func currencyProviderNotesRelativeAgeWhenStaleEnough() async throws {
    let fixture = try makeCurrencyStorage()
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    let store = RateStore(storage: fixture.storage)
    let fixedNow = Date(timeIntervalSince1970: 100_000)
    store.save(
        rates: ["EUR": 1.0, "MYR": 4.0, "USD": 1.0],
        fetchedAt: fixedNow.addingTimeInterval(-2 * 3_600)
    )
    let fetcher = MockRateFetcher(result: .success([:]))
    let provider = CurrencyProvider(store: store, fetcher: fetcher, now: { fixedNow })

    let results = try await provider.results(
        for: ParsedQuery(mode: .general, term: "123myr to usd")
    )

    #expect(results.first?.hero?.note == "Updated 2 hours ago")
}

@MainActor
@Test
func currencyProviderStaleCacheAnswersImmediatelyThenRefreshesInBackground() async throws {
    let fixture = try makeCurrencyStorage()
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    let store = RateStore(storage: fixture.storage)
    let fixedNow = Date(timeIntervalSince1970: 200_000)
    store.save(
        rates: ["EUR": 1.0, "MYR": 4.0, "USD": 1.0],
        fetchedAt: fixedNow.addingTimeInterval(-13 * 3_600)
    )
    let fetcher = MockRateFetcher(
        result: .success(["EUR": 1.0, "MYR": 4.9, "USD": 1.10])
    )
    let provider = CurrencyProvider(store: store, fetcher: fetcher, now: { fixedNow })

    let results = try await provider.results(
        for: ParsedQuery(mode: .general, term: "123myr to usd")
    )

    // Stale answer returns immediately from the OLD rates, without waiting on the network.
    #expect(results.first?.hero?.right == "$30.75")

    await fetcher.waitUntilCalled(atLeast: 1)
    let refreshed = try #require(store.cached())
    #expect(refreshed.rates == ["EUR": 1.0, "MYR": 4.9, "USD": 1.10])
}

@MainActor
@Test
func currencyProviderNoCacheFetchesInlineAndPersists() async throws {
    let fixture = try makeCurrencyStorage()
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    let store = RateStore(storage: fixture.storage)
    let fixedNow = Date(timeIntervalSince1970: 300_000)
    let fetcher = MockRateFetcher(
        result: .success(["EUR": 1.0, "MYR": 4.0, "USD": 1.0])
    )
    let provider = CurrencyProvider(store: store, fetcher: fetcher, now: { fixedNow })

    let results = try await provider.results(
        for: ParsedQuery(mode: .general, term: "123myr to usd")
    )

    #expect(await fetcher.callCount == 1)
    #expect(results.first?.hero?.right == "$30.75")
    #expect(results.first?.hero?.note == nil)
    let persisted = try #require(store.cached())
    #expect(persisted.fetchedAt == fixedNow)
}

@MainActor
@Test
func currencyProviderNoCacheFetchFailureReturnsUnavailableRow() async throws {
    let fixture = try makeCurrencyStorage()
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    let store = RateStore(storage: fixture.storage)
    let fetcher = MockRateFetcher(result: .failure(FetchError.offline))
    let provider = CurrencyProvider(store: store, fetcher: fetcher)

    let results = try await provider.results(
        for: ParsedQuery(mode: .general, term: "123myr to usd")
    )

    #expect(results.count == 1)
    #expect(results.first?.hero == nil)
    #expect(results.first?.title == "Exchange rates unavailable — check connection")
    #expect(results.first?.icon == .symbol("wifi.slash"))
    #expect(store.cached() == nil)
}

private enum FetchError: Error {
    case offline
}

private actor MockRateFetcher: RateFetcher {
    private(set) var callCount = 0
    private var result: Result<[String: Double], Error>
    private var waiters: [(count: Int, continuation: CheckedContinuation<Void, Never>)] = []

    init(result: Result<[String: Double], Error>) {
        self.result = result
    }

    func fetchEURBaseRates() async throws -> [String: Double] {
        callCount += 1
        let ready = waiters.filter { callCount >= $0.count }
        waiters.removeAll { callCount >= $0.count }
        ready.forEach { $0.continuation.resume() }
        return try result.get()
    }

    func waitUntilCalled(atLeast count: Int) async {
        if callCount >= count {
            return
        }
        await withCheckedContinuation { continuation in
            waiters.append((count, continuation))
        }
    }
}

private func makeCurrencyStorage() throws -> (root: URL, storage: Storage) {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    let storage = Storage(baseDirectory: root)
    try storage.ensureDirectories()
    return (root, storage)
}

@MainActor
@Test
func currencyProviderStaleCacheRefreshesOnlyOnce() async throws {
    let fixture = try makeCurrencyStorage()
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    let store = RateStore(storage: fixture.storage)
    let fixedNow = Date(timeIntervalSince1970: 1_000_000)
    store.save(
        rates: ["EUR": 1.0, "MYR": 4.0, "USD": 1.0],
        fetchedAt: fixedNow.addingTimeInterval(-13 * 3_600)
    )
    let fetcher = GatedRateFetcher(rates: ["EUR": 1.0, "MYR": 4.1, "USD": 1.0])
    let provider = CurrencyProvider(store: store, fetcher: fetcher, now: { fixedNow })

    // Two rapid stale-cache queries must share one background refresh.
    _ = try await provider.results(for: ParsedQuery(mode: .general, term: "123myr to usd"))
    _ = try await provider.results(for: ParsedQuery(mode: .general, term: "123myr to usd"))

    await fetcher.waitUntilStarted()
    #expect(await fetcher.startCount == 1)
    await fetcher.release()
}

private actor GatedRateFetcher: RateFetcher {
    private(set) var startCount = 0
    private let rates: [String: Double]
    private var gate: CheckedContinuation<Void, Never>?
    private var startWaiter: CheckedContinuation<Void, Never>?

    init(rates: [String: Double]) {
        self.rates = rates
    }

    func fetchEURBaseRates() async throws -> [String: Double] {
        startCount += 1
        startWaiter?.resume()
        startWaiter = nil
        await withCheckedContinuation { gate = $0 }
        return rates
    }

    func waitUntilStarted() async {
        if startCount > 0 {
            return
        }
        await withCheckedContinuation { startWaiter = $0 }
    }

    func release() {
        gate?.resume()
        gate = nil
    }
}
