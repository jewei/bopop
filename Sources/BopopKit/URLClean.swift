import Foundation

public nonisolated struct CleanedURL: Equatable, Sendable {
    public let original: String
    public let cleaned: String
    public let removedCount: Int
}

public nonisolated enum URLCleaner {
    private static let globalPrefixes = ["utm_", "vero_", "oly_", "pd_rd_", "pf_rd_"]

    // Bare "ref" is overwhelmingly a referral tracker on shared links
    // (raycast.com?ref=product_sidebar, producthunt, medium); the rare
    // functional use (some git-hosting deep links) loses this trade-off.
    private static let globalExact: Set<String> = [
        "fbclid", "gclid", "gclsrc", "dclid", "msclkid", "igshid", "igsh",
        "mc_eid", "mc_cid", "spm", "_hsenc", "_hsmi", "wickedid", "yclid",
        "twclid", "ttclid", "s_kwcid", "ref", "ref_src", "ref_url"
    ]

    private static let amazonExact: Set<String> = ["ref", "tag", "psc", "th", "linkCode", "linkId"]
    private static let youTubeExact: Set<String> = ["si", "pp", "feature"]
    private static let spotifyExact: Set<String> = ["si"]

    /// Returns nil when `raw` is not an http(s) URL with a host.
    public static func clean(_ raw: String) -> CleanedURL? {
        guard let components = URLComponents(string: raw),
            let scheme = components.scheme?.lowercased(),
            scheme == "http" || scheme == "https",
            let host = components.host, !host.isEmpty
        else {
            return nil
        }

        var removedCount = 0
        var rebuilt = components

        if isAmazonHost(host), let strippedPath = stripAmazonRefSegment(components.path) {
            rebuilt.path = strippedPath
            removedCount += 1
        }

        let originalItems = components.queryItems ?? []
        let survivors = originalItems.filter { item in
            guard shouldRemove(name: item.name, host: host) else {
                return true
            }
            removedCount += 1
            return false
        }
        if survivors.count != originalItems.count {
            rebuilt.queryItems = survivors.isEmpty ? nil : survivors
        }

        guard removedCount > 0 else {
            return CleanedURL(original: raw, cleaned: raw, removedCount: 0)
        }

        let cleaned = rebuilt.url?.absoluteString ?? raw
        return CleanedURL(original: raw, cleaned: cleaned, removedCount: removedCount)
    }

    static func middleTruncate(_ string: String, limit: Int = 60) -> String {
        guard string.count > limit else {
            return string
        }
        let keep = limit - 1
        let headCount = keep / 2 + keep % 2
        let tailCount = keep / 2
        let head = string.prefix(headCount)
        let tail = string.suffix(tailCount)
        return "\(head)…\(tail)"
    }

    private static func shouldRemove(name: String, host: String) -> Bool {
        if globalExact.contains(name) {
            return true
        }
        if globalPrefixes.contains(where: { name.hasPrefix($0) }) {
            return true
        }
        if isAmazonHost(host), amazonExact.contains(name) {
            return true
        }
        if isYouTubeHost(host), youTubeExact.contains(name) {
            return true
        }
        if isSpotifyHost(host), spotifyExact.contains(name) {
            return true
        }
        return false
    }

    private static func stripAmazonRefSegment(_ path: String) -> String? {
        var segments = path.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        guard let index = segments.firstIndex(where: { $0.hasPrefix("ref=") }) else {
            return nil
        }
        segments.remove(at: index)
        return segments.joined(separator: "/")
    }

    /// Amazon spans many ccTLDs (amazon.com, amazon.co.uk, amazon.de, ...), so match by
    /// label rather than a fixed suffix list.
    private static func isAmazonHost(_ host: String) -> Bool {
        host.lowercased().split(separator: ".").contains("amazon")
    }

    private static func isYouTubeHost(_ host: String) -> Bool {
        hostSuffixMatches(host, "youtube.com") || hostSuffixMatches(host, "youtu.be")
    }

    private static func isSpotifyHost(_ host: String) -> Bool {
        hostSuffixMatches(host, "open.spotify.com")
    }

    private static func hostSuffixMatches(_ host: String, _ domain: String) -> Bool {
        let host = host.lowercased()
        return host == domain || host.hasSuffix(".\(domain)")
    }
}

public final class URLCleanProvider: ResultProvider {
    public let id: ProviderID = .urlClean

    public init() {}

    public func results(for query: ParsedQuery) async throws -> [SearchResult] {
        guard query.mode == .general else {
            return []
        }

        let trimmed = query.term.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let cleaned = URLCleaner.clean(trimmed), cleaned.removedCount > 0 else {
            return []
        }

        let trackerNoun = cleaned.removedCount == 1 ? "tracker" : "trackers"
        let hero = HeroContent(
            left: URLCleaner.middleTruncate(cleaned.original),
            leftBadge: "Original",
            right: URLCleaner.middleTruncate(cleaned.cleaned),
            rightBadge: "\(cleaned.removedCount) \(trackerNoun) removed"
        )
        return [
            SearchResult(
                id: "urlclean",
                providerID: .urlClean,
                title: cleaned.cleaned,
                icon: .symbol("link"),
                // Preserve the raw term so Ranker gives this result an exact tier.
                keywords: [query.term],
                action: .openURL(cleaned.cleaned),
                secondaryActions: [.copyText(cleaned.cleaned)],
                hero: hero,
                sortHint: 0
            )
        ]
    }
}
