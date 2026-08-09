import os

public nonisolated struct PerformanceSignposter: Sendable {
    public static let disabled = PerformanceSignposter(signposter: .disabled)

    private let signposter: OSSignposter

    public init(category: String) {
        signposter = OSSignposter(
            subsystem: "com.oneone.bopop.performance",
            category: category
        )
    }

    private init(signposter: OSSignposter) {
        self.signposter = signposter
    }

    /// Own the `defer`: `withIntervalSignpost` skips its end event when the
    /// wrapped work throws. Each call gets a fresh id rather than the default
    /// `.exclusive` one — providers run concurrently and a superseded query's
    /// interval can still be open when the next one begins, so a shared id
    /// would pair the wrong begin/end events and report nonsense durations.
    public func interval<T>(
        _ name: StaticString,
        around work: () throws -> T
    ) rethrows -> T {
        let state = signposter.beginInterval(name, id: signposter.makeSignpostID())
        defer { signposter.endInterval(name, state) }
        return try work()
    }

    public func interval<T>(
        _ name: StaticString,
        isolation: isolated (any Actor)? = #isolation,
        around work: () async throws -> T
    ) async rethrows -> T {
        let state = signposter.beginInterval(name, id: signposter.makeSignpostID())
        defer { signposter.endInterval(name, state) }
        return try await work()
    }
}

public nonisolated enum PerformanceSignposts {
    public static let lifecycle = PerformanceSignposter(category: "Lifecycle")
    public static let palette = PerformanceSignposter(category: "Palette")
    public static let catalog = PerformanceSignposter(category: "Catalog")
    public static let query = PerformanceSignposter(category: "Query")
    public static let provider = PerformanceSignposter(category: "Provider")
}
