import Foundation

public nonisolated enum SystemCommandInvocation: Equatable, Sendable {
    case process(executable: String, arguments: [String])
    /// Four-char AppleEvent ID sent to loginwindow. Only the dialog-showing
    /// variants belong here — macOS presents its own confirmation.
    case loginwindowAppleEvent(code: String)
    /// AppleScript source run against Finder via osascript. Triggers macOS's
    /// one-time Automation consent on first use; denial fails quietly.
    case finderScript(source: String)
}

public nonisolated enum SystemCommand: String, CaseIterable, Sendable {
    case lockScreen, sleep, screenSaver, logOut, restart, shutDown, emptyTrash, ejectAll

    public var title: String {
        switch self {
        case .lockScreen: return "Lock Screen"
        case .sleep: return "Sleep"
        case .screenSaver: return "Start Screen Saver"
        case .logOut: return "Log Out…"
        case .restart: return "Restart…"
        case .shutDown: return "Shut Down…"
        case .emptyTrash: return "Empty Trash"
        case .ejectAll: return "Eject All Disks"
        }
    }

    public var keywords: [String] {
        switch self {
        case .lockScreen: return ["lock", "lock screen"]
        case .sleep: return ["sleep"]
        case .screenSaver: return ["screen saver", "saver"]
        case .logOut: return ["log out", "logout"]
        case .restart: return ["restart", "reboot"]
        case .shutDown: return ["shut down", "shutdown", "power off"]
        case .emptyTrash: return ["empty trash", "trash"]
        case .ejectAll: return ["eject", "eject all"]
        }
    }

    public var symbolName: String {
        switch self {
        case .lockScreen: return "lock.fill"
        case .sleep: return "moon.zzz"
        case .screenSaver: return "sparkles.tv"
        case .logOut: return "rectangle.portrait.and.arrow.right"
        case .restart: return "arrow.clockwise.circle"
        case .shutDown: return "power"
        case .emptyTrash: return "trash"
        case .ejectAll: return "eject"
        }
    }

    public var invocation: SystemCommandInvocation {
        switch self {
        case .lockScreen:
            return .process(
                executable: "/System/Library/PrivateFrameworks/login.framework/Versions/Current/Resources/CGSession",
                arguments: ["-suspend"])
        case .sleep:
            return .process(executable: "/usr/bin/pmset", arguments: ["sleepnow"])
        case .screenSaver:
            return .process(executable: "/usr/bin/open", arguments: ["-b", "com.apple.ScreenSaver.Engine"])
        case .logOut: return .loginwindowAppleEvent(code: "logo")
        case .restart: return .loginwindowAppleEvent(code: "rrst")
        case .shutDown: return .loginwindowAppleEvent(code: "rsdn")
        case .emptyTrash:
            return .finderScript(source: "tell application \"Finder\" to empty trash")
        case .ejectAll:
            return .finderScript(source: "tell application \"Finder\" to eject (every disk whose ejectable is true)")
        }
    }
}

public final class SystemCommandsProvider: ResultProvider {
    public let id: ProviderID = .system

    public init() {}

    public func results(for query: ParsedQuery) async throws -> [SearchResult] {
        guard query.mode == .general,
              !query.term.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return []
        }
        return SystemCommand.allCases.enumerated().map { index, command in
            SearchResult(
                id: "system:\(command.rawValue)",
                providerID: .system,
                title: command.title,
                icon: .symbol(command.symbolName),
                keywords: command.keywords,
                badge: "System",
                action: .systemCommand(command),
                sortHint: index
            )
        }
    }
}
