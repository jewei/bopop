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
    case runScript(String)
    case enterMode(Mode)
    case openURL(String)
    case downloadTranslation
    case systemCommand(SystemCommand)
}

public nonisolated struct HeroContent: Equatable, Sendable {
    public let left: String
    public let leftBadge: String?
    public let right: String
    public let rightBadge: String?
    public let note: String?

    public init(
        left: String,
        leftBadge: String? = nil,
        right: String,
        rightBadge: String? = nil,
        note: String? = nil
    ) {
        self.left = left
        self.leftBadge = leftBadge
        self.right = right
        self.rightBadge = rightBadge
        self.note = note
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
        sortHint: Int
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
    }
}
