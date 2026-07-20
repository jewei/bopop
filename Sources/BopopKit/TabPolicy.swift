import Foundation

public nonisolated enum TabKeyAction: Equatable, Sendable {
    case autocomplete(String)
    case cycleTab
}

/// ⇥ cycles the tab row — except while the calculator hero is showing, where
/// it feeds the answer back into the query so calculation can continue.
public nonisolated enum TabKeyPolicy {
    public static func action(hero: SearchResult?) -> TabKeyAction {
        guard let hero, hero.providerID == .calculator,
              case .copyText(let answer) = hero.action else {
            return .cycleTab
        }
        return .autocomplete(answer)
    }
}
