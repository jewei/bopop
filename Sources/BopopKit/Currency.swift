import Foundation
import os

public nonisolated struct CurrencyQuery: Equatable, Sendable {
    public let amount: Double
    public let from: String
    public let to: String

    public init(amount: Double, from: String, to: String) {
        self.amount = amount
        self.from = from
        self.to = to
    }
}

public nonisolated enum CurrencyParser {
    /// Frankfurter (ECB) coverage plus USD/JPY/etc — the only codes we can ever
    /// price, so anything outside this set is an unknown-code rejection.
    public static let supportedCodes: Set<String> = [
        "AUD", "BGN", "BRL", "CAD", "CHF", "CNY", "CZK", "DKK", "EUR", "GBP",
        "HKD", "HUF", "IDR", "ILS", "INR", "ISK", "JPY", "KRW", "MXN", "MYR",
        "NOK", "NZD", "PHP", "PLN", "RON", "SEK", "SGD", "THB", "TRY", "USD",
        "ZAR"
    ]

    private static let symbolTable: [(symbol: String, code: String)] = [
        ("$", "USD"), ("€", "EUR"), ("£", "GBP"), ("¥", "JPY"), ("₩", "KRW"),
        ("₹", "INR"), ("RM", "MYR"), ("S$", "SGD"), ("HK$", "HKD"),
        ("฿", "THB"), ("Rp", "IDR"), ("₱", "PHP")
    ]

    public static func parse(_ term: String) -> CurrencyQuery? {
        let trimmed = term.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let separatorRange = findSeparator(in: trimmed) else {
            return nil
        }

        let prefix = String(trimmed[trimmed.startIndex..<separatorRange.lowerBound])
        let targetToken = String(trimmed[separatorRange.upperBound...])
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard let to = resolveCode(targetToken),
              let (amount, sourceToken) = extractAmountAndToken(prefix),
              let from = resolveCode(sourceToken),
              amount.isFinite, amount > 0 else {
            return nil
        }

        return CurrencyQuery(amount: amount, from: from, to: to)
    }

    /// Leftmost whole-word occurrence of "to"/"in", case-insensitive.
    private static func findSeparator(in text: String) -> Range<String.Index>? {
        let characters = Array(text)
        var index = 0
        while index < characters.count {
            if index + 1 < characters.count {
                let candidate = String(characters[index...index + 1]).lowercased()
                if candidate == "to" || candidate == "in" {
                    let beforeIsBoundary = index == 0 || !characters[index - 1].isLetter
                    let afterIndex = index + 2
                    let afterIsBoundary = afterIndex >= characters.count
                        || !characters[afterIndex].isLetter
                    if beforeIsBoundary, afterIsBoundary {
                        let lower = text.index(text.startIndex, offsetBy: index)
                        let upper = text.index(lower, offsetBy: 2)
                        return lower..<upper
                    }
                }
            }
            index += 1
        }
        return nil
    }

    /// Splits a prefix like "123myr ", "myr 250 ", "$1,200 " into an amount and
    /// its adjacent currency token (whichever side of the digits it sits on).
    private static func extractAmountAndToken(_ prefix: String) -> (amount: Double, token: String)? {
        let characters = Array(prefix)
        var index = 0
        var leadingTokenChars: [Character] = []
        while index < characters.count, !characters[index].isNumber {
            leadingTokenChars.append(characters[index])
            index += 1
        }
        guard index < characters.count else {
            return nil
        }

        var amountChars: [Character] = []
        var hasDot = false
        while index < characters.count {
            let character = characters[index]
            if character.isNumber || character == "," {
                amountChars.append(character)
                index += 1
            } else if character == ".", !hasDot {
                hasDot = true
                amountChars.append(character)
                index += 1
            } else {
                break
            }
        }

        let trailingToken = String(characters[index...])
            .trimmingCharacters(in: .whitespaces)
        let leadingToken = String(leadingTokenChars)
            .trimmingCharacters(in: .whitespaces)
        let amountString = String(amountChars).replacingOccurrences(of: ",", with: "")
        guard let amount = Double(amountString) else {
            return nil
        }

        let token = !leadingToken.isEmpty ? leadingToken : trailingToken
        guard !token.isEmpty else {
            return nil
        }
        return (amount, token)
    }

    private static func resolveCode(_ raw: String) -> String? {
        let token = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else {
            return nil
        }
        // Symbols still have to clear the same supportedCodes gate as bare
        // codes — a symbol whose code we can never price (no ECB rate) must
        // be rejected here, not surface as a silent empty result downstream.
        for entry in symbolTable where token.caseInsensitiveCompare(entry.symbol) == .orderedSame {
            return supportedCodes.contains(entry.code) ? entry.code : nil
        }
        let upper = token.uppercased()
        guard supportedCodes.contains(upper) else {
            return nil
        }
        return upper
    }
}

public protocol RateFetcher: Sendable {
    func fetchEURBaseRates() async throws -> [String: Double]
}

public final class LiveRateFetcher: RateFetcher {
    private struct Response: Decodable {
        let rates: [String: Double]
    }

    private static let endpoint = URL(
        string: "https://api.frankfurter.dev/v1/latest?base=EUR"
    )!

    private let session: URLSession

    public init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 5
        session = URLSession(configuration: configuration)
    }

    public func fetchEURBaseRates() async throws -> [String: Double] {
        let (data, _) = try await session.data(from: Self.endpoint)
        let response = try JSONDecoder().decode(Response.self, from: data)
        var rates = response.rates
        rates["EUR"] = 1.0
        return rates
    }
}

public nonisolated struct CachedRates: Codable, Equatable, Sendable {
    public let rates: [String: Double]
    public let fetchedAt: Date

    public init(rates: [String: Double], fetchedAt: Date) {
        self.rates = rates
        self.fetchedAt = fetchedAt
    }

    public func convert(_ query: CurrencyQuery) -> Double? {
        guard let fromRate = rates[query.from], let toRate = rates[query.to],
              fromRate != 0 else {
            return nil
        }
        return query.amount / fromRate * toRate
    }

    public func isStale(now: Date) -> Bool {
        now.timeIntervalSince(fetchedAt) > 12 * 3_600
    }
}

public final class RateStore {
    private static let version = 1

    private let storage: Storage
    // Populated on first load and kept fresh by save() — CurrencyProvider
    // calls cached() once per keystroke, so without this every character
    // typed re-reads and re-decodes rates.json from disk.
    private var memoryCache: CachedRates?
    private var hasLoaded = false

    public init(storage: Storage) {
        self.storage = storage
    }

    public func cached() -> CachedRates? {
        if hasLoaded {
            return memoryCache
        }
        let loaded = storage.load(
            CachedRates.self,
            expectedVersion: Self.version,
            from: storage.ratesFileURL
        )
        memoryCache = loaded
        hasLoaded = true
        return loaded
    }

    public func save(rates: [String: Double], fetchedAt: Date) {
        let cachedRates = CachedRates(rates: rates, fetchedAt: fetchedAt)
        try? storage.save(
            cachedRates,
            version: Self.version,
            to: storage.ratesFileURL
        )
        memoryCache = cachedRates
        hasLoaded = true
    }
}

public nonisolated final class CurrencyProvider: ResultProvider {
    public let id: ProviderID = .currency

    /// EUR-base cross-rates convert every code, but only these have a
    /// recognizable symbol; everything else falls back to "amount CODE".
    private static let displaySymbols: [String: String] = [
        "USD": "$", "EUR": "€", "GBP": "£", "JPY": "¥", "KRW": "₩",
        "INR": "₹", "MYR": "RM", "SGD": "S$", "HKD": "HK$", "THB": "฿",
        "IDR": "Rp", "PHP": "₱"
    ]

    private static let freshNoteWindow: TimeInterval = 15 * 60

    private let store: RateStore
    private let fetcher: RateFetcher
    private let now: @Sendable () -> Date
    // Once this provider runs off the main actor, two overlapping generations
    // could format on this shared instance from different threads at once —
    // RelativeDateTimeFormatter is not thread-safe, so guard it with a lock
    // rather than constructing one per call.
    private let relativeDateFormatter: FormatterBox<RelativeDateTimeFormatter>
    // Guards the refresh-in-flight flag against the same cross-thread race
    // now that results(for:) is nonisolated.
    private let refreshInFlight = OSAllocatedUnfairLock(initialState: false)

    public init(
        store: RateStore,
        fetcher: RateFetcher,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.store = store
        self.fetcher = fetcher
        self.now = now
        let formatter = RelativeDateTimeFormatter()
        formatter.dateTimeStyle = .named
        formatter.locale = Locale(identifier: "en_US")
        relativeDateFormatter = FormatterBox(formatter)
    }

    public nonisolated func results(for query: ParsedQuery) async throws -> [SearchResult] {
        guard query.mode == .general, let parsed = CurrencyParser.parse(query.term) else {
            return []
        }

        // RateStore stays MainActor-isolated (its memoryCache/hasLoaded are
        // only safe under single-threaded access) — snapshot through it
        // rather than relaxing its isolation.
        if let cached = await MainActor.run(body: { store.cached() }) {
            if cached.isStale(now: now()) {
                refreshInBackground()
            }
            return makeResults(for: parsed, rawTerm: query.term, rates: cached)
        }

        guard let freshRates = try? await fetcher.fetchEURBaseRates() else {
            return [Self.unavailableResult()]
        }
        let fetchedAt = now()
        await MainActor.run { store.save(rates: freshRates, fetchedAt: fetchedAt) }
        return makeResults(
            for: parsed,
            rawTerm: query.term,
            rates: CachedRates(rates: freshRates, fetchedAt: fetchedAt)
        )
    }

    /// Cache is stale but still answerable — hand back the stale answer now
    /// and let this unstructured task refresh it for next time without
    /// blocking the current query.
    private nonisolated func refreshInBackground() {
        // One refresh at a time — while the cache is stale, every keystroke of
        // the query re-enters here, and each must not become its own request.
        // The test-and-set has to be atomic now that multiple provider
        // invocations can race on this flag from different threads.
        let shouldStart = refreshInFlight.withLock { inFlight -> Bool in
            guard !inFlight else {
                return false
            }
            inFlight = true
            return true
        }
        guard shouldStart else {
            return
        }
        Task {
            defer { refreshInFlight.withLock { $0 = false } }
            guard let freshRates = try? await fetcher.fetchEURBaseRates() else {
                return
            }
            let fetchedAt = now()
            await MainActor.run { store.save(rates: freshRates, fetchedAt: fetchedAt) }
        }
    }

    private nonisolated func makeResults(
        for query: CurrencyQuery,
        rawTerm: String,
        rates: CachedRates
    ) -> [SearchResult] {
        guard let converted = rates.convert(query) else {
            return []
        }

        let left = "\(Self.formattedAmount(query.amount)) \(query.from)"
        let targetAmount = Self.formattedTargetAmount(converted)
        let right = Self.displaySymbols[query.to].map { "\($0)\(targetAmount)" }
            ?? "\(targetAmount) \(query.to)"
        let leftBadge = Self.currencyDisplayName(query.from)
        let rightBadge = Self.currencyDisplayName(query.to)

        let age = now().timeIntervalSince(rates.fetchedAt)
        let note: String? = age < Self.freshNoteWindow
            ? nil
            : "Updated \(relativeDateFormatter.withLock { $0.localizedString(for: rates.fetchedAt, relativeTo: now()) })"

        return [
            SearchResult(
                id: "currency",
                providerID: .currency,
                title: "\(left) = \(right)",
                icon: .symbol("dollarsign.circle"),
                keywords: [rawTerm],
                action: .copyText(targetAmount),
                hero: HeroContent(
                    left: left,
                    leftBadge: leftBadge,
                    right: right,
                    rightBadge: rightBadge,
                    note: note
                ),
                sortHint: 0
            )
        ]
    }

    private nonisolated static func unavailableResult() -> SearchResult {
        SearchResult(
            id: "currency:unavailable",
            providerID: .currency,
            title: "Exchange rates unavailable — check connection",
            icon: .symbol("wifi.slash"),
            action: .copyText(""),
            sortHint: 0
        )
    }

    // Built once instead of per call — CurrencyProvider.results(for:) runs on
    // every keystroke of a matching query, and NumberFormatter construction is
    // expensive enough to notice at that rate. NumberFormatter itself is not
    // thread-safe, and this static instance is now reachable from whichever
    // thread the task group happens to run this provider's body on, so every
    // use goes through this lock instead of relying on MainActor serialization.
    private static let amountFormatter: FormatterBox<NumberFormatter> = {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = true
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 2
        return FormatterBox(formatter)
    }()

    private static let targetAmountFormatter: FormatterBox<NumberFormatter> = {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = true
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        return FormatterBox(formatter)
    }()

    private nonisolated static func formattedAmount(_ value: Double) -> String {
        amountFormatter.withLock { $0.string(from: NSNumber(value: value)) } ?? String(value)
    }

    private nonisolated static func formattedTargetAmount(_ value: Double) -> String {
        targetAmountFormatter.withLock { $0.string(from: NSNumber(value: value)) }
            ?? String(format: "%.2f", value)
    }

    private nonisolated static func currencyDisplayName(_ code: String) -> String? {
        Locale(identifier: "en_US").localizedString(forCurrencyCode: code)
    }
}
