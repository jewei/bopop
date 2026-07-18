import Foundation
import os

public final class QueryEngine {
    public struct Update: Sendable {
        public let results: [SearchResult]
        public let generation: Int
        public let isFinal: Bool

        public init(results: [SearchResult], generation: Int, isFinal: Bool) {
            self.results = results
            self.generation = generation
            self.isFinal = isFinal
        }
    }

    public var onUpdate: ((Update) -> Void)?

    private let providers: [Mode: [any ResultProvider]]
    private let debounce: [Mode: Duration]
    private let frecencyFor: (String) -> Double
    private let providerWeights: [ProviderID: Double]
    private var generation = 0
    private var task: Task<Void, Never>?

    public init(
        providers: [Mode: [any ResultProvider]],
        debounce: [Mode: Duration] = [.fileSearch: .milliseconds(250)],
        frecencyFor: @escaping (String) -> Double = { _ in 0 },
        providerWeights: [ProviderID: Double] = Ranker.defaultWeights
    ) {
        self.providers = providers
        self.debounce = debounce
        self.frecencyFor = frecencyFor
        self.providerWeights = providerWeights
    }

    public func update(raw: String, stickyMode: Mode) {
        generation += 1
        task?.cancel()

        let taskGeneration = generation
        let query = QueryParser.parse(raw: raw, stickyMode: stickyMode)
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
                emit(results: [], generation: taskGeneration, isFinal: true)
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
        var accumulated: [SearchResult] = []
        var remaining = providers.count

        await withTaskGroup(of: ProviderCompletion.self) { group in
            for provider in providers {
                let providerID = provider.id
                group.addTask {
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

            for await completion in group {
                remaining -= 1
                guard !Task.isCancelled, taskGeneration == generation else {
                    group.cancelAll()
                    return
                }

                switch completion {
                case let .results(_, results):
                    accumulated.append(contentsOf: results)
                case let .failure(providerID, message):
                    Self.logger.error(
                        "Provider \(providerID.rawValue, privacy: .public) failed: \(message, privacy: .private)"
                    )
                case .cancelled:
                    continue
                }

                let ranked = Ranker.rank(
                    accumulated,
                    query: query.term,
                    frecencyFor: frecencyFor,
                    providerWeights: providerWeights
                )
                emit(
                    results: ranked,
                    generation: taskGeneration,
                    isFinal: remaining == 0
                )
            }
        }
    }

    private func emit(
        results: [SearchResult],
        generation taskGeneration: Int,
        isFinal: Bool
    ) {
        guard !Task.isCancelled, taskGeneration == generation else {
            return
        }
        onUpdate?(
            Update(
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
    }
}
