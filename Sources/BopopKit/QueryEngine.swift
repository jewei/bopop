import Foundation
import os

public final class QueryEngine {
    public struct Update: Sendable {
        /// The query this update answers.
        ///
        /// Carried back so the receiver can tell which query produced these
        /// results instead of re-deriving it from whatever the query field
        /// happens to hold by the time the update lands. Re-parsing on receipt
        /// is a second clock: it can disagree with the query that was actually
        /// run, which is how a mode prefix ends up drawn against the previous
        /// mode's rows.
        public let query: ParsedQuery
        public let results: [SearchResult]
        public let generation: Int
        public let isFinal: Bool

        public init(
            query: ParsedQuery,
            results: [SearchResult],
            generation: Int,
            isFinal: Bool
        ) {
            self.query = query
            self.results = results
            self.generation = generation
            self.isFinal = isFinal
        }
    }

    public var onUpdate: ((Update) -> Void)?

    private let providers: [Mode: [any ResultProvider]]
    private let debounce: [Mode: Duration]
    private let settle: Duration
    private let frecencyFor: (String) -> Double
    private let providerWeights: [ProviderID: Double]
    private var generation = 0
    private var task: Task<Void, Never>?

    /// - Parameter settle: How long results are allowed to keep accumulating
    ///   once the first of them lands. Providers finish at wildly different
    ///   times, and publishing per completion made the palette repaint up to
    ///   twelve times per keystroke — first blank, then with rows that a
    ///   slower, higher-ranking provider promptly shoved down. Collecting for
    ///   one short window instead means a keystroke normally costs one paint.
    ///   It is a window, not a wait: anything still outstanding when the window
    ///   closes publishes what has landed and keeps going, so a slow provider
    ///   (Currency, on a bad network) can never hold the list back. `.zero`
    ///   restores per-completion publishing. Either way an interim update is
    ///   never empty — publishing the empty accumulated list on the way to a
    ///   populated one is what the user saw as a blink.
    public init(
        providers: [Mode: [any ResultProvider]],
        debounce: [Mode: Duration] = [.fileSearch: .milliseconds(250)],
        settle: Duration = .milliseconds(50),
        frecencyFor: @escaping (String) -> Double = { _ in 0 },
        providerWeights: [ProviderID: Double] = Ranker.defaultWeights
    ) {
        self.providers = providers
        self.debounce = debounce
        self.settle = settle
        self.frecencyFor = frecencyFor
        self.providerWeights = providerWeights
    }

    /// Runs an already-parsed query.
    ///
    /// The engine deliberately does not parse: `QueryParser` is owned by the
    /// caller so that exactly one parse exists per keystroke, and the parse
    /// that ran is the parse reported back on `Update.query`.
    public func update(query: ParsedQuery) {
        generation += 1
        task?.cancel()

        let taskGeneration = generation
        let modeProviders = providers[query.mode, default: []]
        task = Task { [weak self] in
            guard let self else {
                return
            }

            do {
                if let delay = debounce[query.mode], !query.term.isEmpty {
                    try await Task.sleep(for: delay)
                }
            } catch is CancellationError {
                return
            } catch {
                return
            }

            guard !Task.isCancelled, taskGeneration == generation else {
                return
            }

            if modeProviders.isEmpty {
                emit(
                    query: query,
                    results: [],
                    generation: taskGeneration,
                    isFinal: true
                )
                return
            }

            await runProviders(
                modeProviders,
                query: query,
                generation: taskGeneration
            )
        }
    }

    public func cancel() {
        task?.cancel()
        task = nil
    }

    private func runProviders(
        _ providers: [any ResultProvider],
        query: ParsedQuery,
        generation taskGeneration: Int
    ) async {
        await PerformanceSignposts.query.interval("Query Providers") {
            await collectProviderResults(
                providers,
                query: query,
                generation: taskGeneration
            )
        }
    }

    private func collectProviderResults(
        _ providers: [any ResultProvider],
        query: ParsedQuery,
        generation taskGeneration: Int
    ) async {
        var accumulated: [SearchResult] = []
        var remaining = providers.count
        // Results that have landed since the last publish, and whether a
        // window is already counting down for them. The window is armed on
        // demand rather than running free: a provider that never returns would
        // otherwise keep re-arming a timer forever behind an idle palette.
        var hasUnpublishedResults = false
        var isSettleWindowArmed = false
        let settleWindow = settle

        func armSettleWindow(in group: inout TaskGroup<ProviderCompletion>) {
            guard settleWindow > .zero, !isSettleWindowArmed else {
                return
            }
            isSettleWindowArmed = true
            group.addTask {
                try? await Task.sleep(for: settleWindow)
                return .settled
            }
        }

        await withTaskGroup(of: ProviderCompletion.self) { group in
            for provider in providers {
                let providerID = provider.id
                group.addTask {
                    await PerformanceSignposts.provider.interval("Provider Results") {
                        do {
                            return .results(
                                providerID,
                                try await provider.results(for: query)
                            )
                        } catch is CancellationError {
                            return .cancelled
                        } catch {
                            return .failure(providerID, String(describing: error))
                        }
                    }
                }
            }

            for await completion in group {
                guard !Task.isCancelled, taskGeneration == generation else {
                    group.cancelAll()
                    return
                }

                if case .settled = completion {
                    // The window closed with providers still outstanding, so
                    // publish what has landed: the window bounds how long a
                    // slow provider can delay results already in hand, it
                    // never lets one block them.
                    isSettleWindowArmed = false
                    if hasUnpublishedResults, !accumulated.isEmpty {
                        hasUnpublishedResults = false
                        publish(
                            accumulated,
                            query: query,
                            generation: taskGeneration,
                            isFinal: false
                        )
                    }
                    continue
                }

                // Decremented for every provider outcome, cancellation
                // included: skipping it when the LAST provider is the
                // cancelled one would strand `isFinal` at false forever and
                // pin File mode's footer on "Searching…" until the next
                // keystroke.
                remaining -= 1

                switch completion {
                case let .results(_, results):
                    accumulated.append(contentsOf: results)
                    if !results.isEmpty {
                        hasUnpublishedResults = true
                        // Start the clock on rows the user cannot see yet.
                        armSettleWindow(in: &group)
                    }
                case let .failure(providerID, message):
                    Self.logger.error(
                        "Provider \(providerID.rawValue, privacy: .public) failed: \(message, privacy: .private)"
                    )
                case .cancelled, .settled:
                    break
                }

                if remaining == 0 {
                    publish(
                        accumulated,
                        query: query,
                        generation: taskGeneration,
                        isFinal: true
                    )
                    // The next settle task is still sleeping; nothing is left
                    // to publish, so end the group rather than wait it out.
                    group.cancelAll()
                    return
                }

                // With a settle window, interim publishes belong to the timer
                // alone. Without one, every completion publishes — but never a
                // blank list, which is what made the palette blink: the six
                // providers that matched nothing each painted the empty
                // accumulated list before the matching one landed.
                if settleWindow <= .zero, hasUnpublishedResults, !accumulated.isEmpty {
                    hasUnpublishedResults = false
                    publish(
                        accumulated,
                        query: query,
                        generation: taskGeneration,
                        isFinal: false
                    )
                }
            }
        }
    }

    private func publish(
        _ accumulated: [SearchResult],
        query: ParsedQuery,
        generation taskGeneration: Int,
        isFinal: Bool
    ) {
        let ranked = PerformanceSignposts.query.interval("Rank Results") {
            Ranker.rank(
                accumulated,
                query: query.term,
                frecencyFor: frecencyFor,
                providerWeights: providerWeights
            )
        }
        emit(
            query: query,
            results: ranked,
            generation: taskGeneration,
            isFinal: isFinal
        )
    }

    private func emit(
        query: ParsedQuery,
        results: [SearchResult],
        generation taskGeneration: Int,
        isFinal: Bool
    ) {
        guard !Task.isCancelled, taskGeneration == generation else {
            return
        }
        onUpdate?(
            Update(
                query: query,
                results: results,
                generation: taskGeneration,
                isFinal: isFinal
            )
        )
    }

    private static let logger = Logger(
        subsystem: "com.oneone.bopop",
        category: "engine"
    )

    private enum ProviderCompletion: Sendable {
        case results(ProviderID, [SearchResult])
        case failure(ProviderID, String)
        case cancelled
        /// A settle window elapsed with providers still outstanding.
        case settled
    }
}
