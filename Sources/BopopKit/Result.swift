import Foundation

public nonisolated enum ProviderID: String, Hashable, Sendable {
    case apps
    case files
    case calculator
    case clipboard
    case scripts
    case commands
    case currency
    case time
    case emoji
    case urlClean
    case translation
    case webSearch
    case system
    case customSearch
    case snippets
    case dictionary
}

public nonisolated enum IconRef: Equatable, Sendable {
    case appBundle(String)
    case file(String)
    case symbol(String)
    case none
}

public nonisolated enum ResultAction: Equatable, Sendable {
    case openApp(String)
    case openFile(String)
    case copyText(String)
    case clearClipboardHistory
    case pinClipboard(Date)
    case unpinClipboard(Date)
    case runScript(String)
    case enterMode(Mode)
    case openURL(String)
    case downloadTranslation
    case systemCommand(SystemCommand)
    case revealFile(String)
}

public nonisolated struct HeroContent: Equatable, Sendable {
    public let left: String
    public let leftBadge: String?
    public let right: String
    public let rightBadge: String?
    public let note: String?
    /// The plain-text answer ⇥ should feed back into the query field, e.g.
    /// the calculator's ungrouped result. `nil` (the default) means ⇥
    /// should cycle tabs as usual instead — see `TabKeyPolicy`.
    public let autocompleteText: String?

    public init(
        left: String,
        leftBadge: String? = nil,
        right: String,
        rightBadge: String? = nil,
        note: String? = nil,
        autocompleteText: String? = nil
    ) {
        self.left = left
        self.leftBadge = leftBadge
        self.right = right
        self.rightBadge = rightBadge
        self.note = note
        self.autocompleteText = autocompleteText
    }
}

public nonisolated struct SearchResult: Identifiable, Equatable, Sendable {
    public let id: String
    public let providerID: ProviderID
    public let title: String
    public let subtitle: String?
    public let icon: IconRef
    public let keywords: [String]
    public let badge: String?
    public let action: ResultAction
    public let secondaryActions: [ResultAction]
    public let hero: HeroContent?
    public let sortHint: Int
    /// Marks a result as a fallback row that never competes on match score —
    /// it's retained even when the query doesn't tier-match it, and always
    /// sorts after every non-fallback result, in stable input order. See
    /// `Ranker.rank`. `WebSearchProvider` is the only current producer.
    public let isFallback: Bool

    public init(
        id: String,
        providerID: ProviderID,
        title: String,
        subtitle: String? = nil,
        icon: IconRef = .none,
        keywords: [String] = [],
        badge: String? = nil,
        action: ResultAction,
        secondaryActions: [ResultAction] = [],
        hero: HeroContent? = nil,
        sortHint: Int,
        isFallback: Bool = false
    ) {
        self.id = id
        self.providerID = providerID
        self.title = title
        self.subtitle = subtitle
        self.icon = icon
        self.keywords = keywords
        self.badge = badge
        self.action = action
        self.secondaryActions = secondaryActions
        self.hero = hero
        self.sortHint = sortHint
        self.isFallback = isFallback
    }
}
