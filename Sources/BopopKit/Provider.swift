import Foundation

public protocol ResultProvider: Sendable {
    var id: ProviderID { get }
    func results(for query: ParsedQuery) async throws -> [SearchResult]
}
