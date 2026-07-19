import Foundation

public nonisolated enum HeroPresentation {
    public static func split(_ ranked: [SearchResult]) -> (hero: SearchResult?, rows: [SearchResult]) {
        guard let top = ranked.first, top.hero != nil else {
            return (nil, ranked)
        }
        return (top, Array(ranked.dropFirst()))
    }
}
