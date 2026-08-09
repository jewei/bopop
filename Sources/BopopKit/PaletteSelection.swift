import Foundation

public nonisolated enum PaletteSelection {
    public static let heroIndex = -1

    public struct UpdateDecision: Equatable, Sendable {
        public let index: Int
        public let restorationID: String?

        public init(index: Int, restorationID: String?) {
            self.index = index
            self.restorationID = restorationID
        }
    }

    public static func afterUpdate(
        rowIDs: [String],
        hasHero: Bool,
        restorationID: String?,
        isFinal: Bool
    ) -> UpdateDecision {
        let restoredIndex = restorationID.flatMap(rowIDs.firstIndex)
        let index: Int
        if let restoredIndex {
            index = restoredIndex
        } else if hasHero {
            index = heroIndex
        } else {
            index = 0
        }
        return UpdateDecision(
            index: index,
            restorationID: isFinal ? nil : restorationID
        )
    }

    public static func moveTable(
        index: Int,
        by offset: Int,
        rowCount: Int,
        hasHero: Bool
    ) -> Int {
        let lowerBound = hasHero ? heroIndex : 0
        let upperBound = rowCount - 1
        guard upperBound >= lowerBound else {
            return index
        }
        return min(max(index + offset, lowerBound), upperBound)
    }

    public static func moveGrid(
        index: Int,
        by offset: Int,
        columns: Int,
        rowCount: Int
    ) -> Int {
        guard rowCount > 0 else {
            return index
        }
        return GridNavigation.move(
            index: max(index, 0),
            by: offset,
            columns: columns,
            count: rowCount
        )
    }

    public static func selectedID(
        index: Int,
        heroID: String?,
        rowIDs: [String]
    ) -> String? {
        if index == heroIndex {
            return heroID
        }
        guard rowIDs.indices.contains(index) else {
            return nil
        }
        return rowIDs[index]
    }
}
