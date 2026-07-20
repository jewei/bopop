import CoreServices
import Foundation

enum DictionaryLookup {
    /// On-device definition via DictionaryServices. No network, no permission.
    nonisolated static func definition(for word: String) -> String? {
        let range = CFRangeMake(0, word.utf16.count)
        guard let definition = DCSCopyTextDefinition(nil, word as CFString, range) else {
            return nil
        }
        return definition.takeRetainedValue() as String
    }
}
