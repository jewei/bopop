import Foundation

public enum ProviderID: String, Hashable, Sendable {
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
    case password
}

public enum IconRef: Equatable, Sendable {
    case appBundle(String)
    case file(String)
    case symbol(String)
    case none
}

public enum ResultAction: Equatable, Sendable {
    public enum Role: Equatable, Sendable {
        case disabled
        case open
        case copy
        case clear
        case pin
        case unpin
        case quit
        case hide
        case run
        case select
        case download
        case reveal

        public var verb: String? {
            switch self {
            case .disabled: nil
            case .open: "open"
            case .copy: "copy"
            case .clear: "clear"
            case .pin: "pin"
            case .unpin: "unpin"
            case .quit: "quit"
            case .hide: "hide"
            case .run: "run"
            case .select: "select"
            case .download: "download"
            case .reveal: "reveal"
            }
        }
    }

    /// An informational result with no executable primary action. Keeping
    /// this explicit avoids disguising a disabled row as a mode change or an
    /// empty clipboard write.
    case disabled
    case openApp(String)
    case openFile(String)
    case copyText(String)
    /// A copy the pasteboard must be told is secret — a generated password.
    /// The write declares `ClipboardCapturePolicy.sensitiveTypes`, so Bopop's
    /// own watcher and every clipboard manager honouring the convention leave
    /// it out of history. Distinct from `copyText` precisely so that marking
    /// is not something a provider can forget to ask for.
    case copySecret(String)
    case clearClipboardHistory
    case pinClipboard(UUID)
    case unpinClipboard(UUID)
    /// Bundle identifier — `NSRunningApplication` is looked up by that, and a
    /// path wouldn't survive an app being moved while running.
    case quitApp(String)
    /// `SearchResult.id` of a result to stop showing. See `VisibilityStore`.
    case hideResult(String)
    case runScript(String)
    case enterMode(Mode)
    case openURL(String)
    case downloadTranslation
    case systemCommand(SystemCommand)
    case revealFile(String)

    public var isExecutable: Bool {
        role != .disabled
    }

    public var role: Role {
        switch self {
        case .disabled: .disabled
        case .openApp, .openFile, .openURL: .open
        case .copyText, .copySecret: .copy
        case .clearClipboardHistory: .clear
        case .pinClipboard: .pin
        case .unpinClipboard: .unpin
        case .quitApp: .quit
        case .hideResult: .hide
        case .runScript, .systemCommand: .run
        case .enterMode: .select
        case .downloadTranslation: .download
        case .revealFile: .reveal
        }
    }
}

public struct HeroContent: Equatable, Sendable {
    public let left: String
    public let leftBadge: String?
    public let right: String
    public let rightBadge: String?
    public let note: String?
    /// The plain-text answer ⇥ should feed back into the query field, e.g.
    /// the calculator's ungrouped result. `nil` (the default) means ⇥
    /// should cycle tabs as usual instead — see `PaletteState.tab(shift:)`.
    public let autocompleteText: String?
    /// True when `right` is an opaque payload rather than prose — a generated
    /// password. Word wrapping breaks such a value at its punctuation, which
    /// both reads as ragged and wastes most of the second line: a 40-character
    /// password needed four lines against a two-line cap and was silently
    /// truncated in the card while the row below it showed the value in full.
    public let rightWrapsByCharacter: Bool

    public init(
        left: String,
        leftBadge: String? = nil,
        right: String,
        rightBadge: String? = nil,
        note: String? = nil,
        autocompleteText: String? = nil,
        rightWrapsByCharacter: Bool = false
    ) {
        self.left = left
        self.leftBadge = leftBadge
        self.right = right
        self.rightBadge = rightBadge
        self.note = note
        self.autocompleteText = autocompleteText
        self.rightWrapsByCharacter = rightWrapsByCharacter
    }
}

public struct SearchResult: Identifiable, Equatable, Sendable {
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
