import Foundation

public nonisolated enum MatchTier: Int, Comparable, Sendable {
    case none = 0
    case subsequence
    case substring
    case wordBoundary
    case prefix
    case exact

    public static func < (lhs: MatchTier, rhs: MatchTier) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

public nonisolated enum Ranker {
    public static let defaultWeights: [ProviderID: Double] = [
        .urlClean: 112,
        .currency: 110,
        .translation: 110,
        .time: 108,
        .calculator: 100,
        .commands: 60,
        .apps: 50,
        .scripts: 40,
        .clipboard: 30,
        .emoji: 45,
        .files: 20,
        .system: 55,
        .customSearch: 105,
        .snippets: 35
    ]

    public static func tier(query: String, candidate: String) -> MatchTier {
        let query = folded(query)
        let candidate = folded(candidate)

        if query == candidate {
            return .exact
        }
        if candidate.hasPrefix(query) {
            return .prefix
        }
        if isWordBoundaryMatch(query: query, candidate: candidate) {
            return .wordBoundary
        }
        if candidate.contains(query) {
            return .substring
        }
        if isSubsequence(query: query, candidate: candidate) {
            return .subsequence
        }
        return .none
    }

    public static func score(
        _ result: SearchResult,
        query: String,
        frecency: Double,
        providerWeight: Double
    ) -> Double {
        let tier = bestTier(for: result, query: query)
        return Double(tier.rawValue * 1_000) + providerWeight + min(frecency, 999)
    }

    public static func rank(
        _ results: [SearchResult],
        query: String,
        frecencyFor: (String) -> Double,
        providerWeights: [ProviderID: Double]
    ) -> [SearchResult] {
        let ranked = results.compactMap { result -> RankedResult? in
            let tier = bestTier(for: result, query: query)
            guard query.isEmpty || tier != .none || result.providerID == .webSearch else {
                return nil
            }
            return RankedResult(
                result: result,
                score: score(
                    result,
                    query: query,
                    frecency: frecencyFor(result.id),
                    providerWeight: providerWeights[result.providerID, default: 0]
                )
            )
        }

        return ranked.sorted { lhs, rhs in
            // Web search is always a fallback row: it never competes on score,
            // it just trails every other result, in stable input order.
            let lhsIsWebSearch = lhs.result.providerID == .webSearch
            let rhsIsWebSearch = rhs.result.providerID == .webSearch
            if lhsIsWebSearch != rhsIsWebSearch {
                return rhsIsWebSearch
            }
            if lhsIsWebSearch {
                return false
            }
            if lhs.score != rhs.score {
                return lhs.score > rhs.score
            }
            if query.isEmpty, lhs.result.sortHint != rhs.result.sortHint {
                return lhs.result.sortHint < rhs.result.sortHint
            }

            let titleOrder = lhs.result.title.localizedStandardCompare(rhs.result.title)
            if titleOrder != .orderedSame {
                return titleOrder == .orderedAscending
            }
            if lhs.result.sortHint != rhs.result.sortHint {
                return lhs.result.sortHint < rhs.result.sortHint
            }
            return lhs.result.id < rhs.result.id
        }.map(\.result)
    }

    private static func bestTier(for result: SearchResult, query: String) -> MatchTier {
        guard !query.isEmpty else {
            return .exact
        }

        return ([result.title] + result.keywords)
            .map { tier(query: query, candidate: $0) }
            .max() ?? .none
    }

    private static func folded(_ value: String) -> String {
        value.folding(
            options: [.caseInsensitive, .diacriticInsensitive],
            locale: nil
        )
    }

    private static func isWordBoundaryMatch(query: String, candidate: String) -> Bool {
        guard !query.isEmpty else {
            return false
        }

        let words = candidate.split { !$0.isLetter && !$0.isNumber }
        if words.contains(where: { $0.hasPrefix(query) }) {
            return true
        }

        let initials = words.compactMap(\.first)
        var initialIndex = initials.startIndex
        for character in query {
            guard let matchIndex = initials[initialIndex...].firstIndex(of: character) else {
                return false
            }
            initialIndex = initials.index(after: matchIndex)
        }
        return true
    }

    private static func isSubsequence(query: String, candidate: String) -> Bool {
        guard !query.isEmpty else {
            return true
        }

        var queryIndex = query.startIndex
        for character in candidate where character == query[queryIndex] {
            queryIndex = query.index(after: queryIndex)
            if queryIndex == query.endIndex {
                return true
            }
        }
        return false
    }

    private struct RankedResult {
        let result: SearchResult
        let score: Double
    }
}
