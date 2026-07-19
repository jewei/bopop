import AppKit
import BopopKit
import SwiftUI
import Translation

/// `Translator` backed by Apple's on-device `Translation` framework.
///
/// `TranslationSession` can only be obtained through the SwiftUI
/// `.translationTask(_:action:)` view modifier, so this class hosts a
/// hidden 1×1 `NSHostingView` inside a persistent, never-visible offscreen
/// window (alpha 0, level well below `.normal`) that lives for the app's
/// entire lifetime. Requests from `translate(_:to:)` are bridged into that
/// view's long-running task via an `AsyncStream`; the task drains the
/// stream and fulfills each request with `session.translate(_:)`.
///
/// The class is `final` and isolated to the app target's default actor
/// (`MainActor`, per `Package.swift`'s `.defaultIsolation`), which is what
/// lets it satisfy `Translator: Sendable` without `@unchecked Sendable`:
/// every stored property is only ever touched on the main actor, so the
/// compiler can prove there's no data race across actor boundaries — the
/// same pattern `CurrencyProvider`/`TranslationProvider` already use in
/// BopopKit for their own default-isolated target.
@MainActor
final class AppleTranslator: Translator {
    private enum QueueItem: Sendable {
        case translate(text: String, continuation: CheckedContinuation<String, Error>)
        case prepareDownload
    }

    @MainActor
    private final class HostState: ObservableObject {
        @Published var configuration: TranslationSession.Configuration?
    }

    /// The drain loop lives directly inside the `.translationTask` closure
    /// (rather than being handed off to a separate `AppleTranslator`
    /// method) so `TranslationSession` — which is not `Sendable` — never
    /// has to cross an isolation boundary; only the `Sendable` `stream`
    /// and its `Sendable` `QueueItem`s do.
    private struct HostView: View {
        @ObservedObject var state: HostState
        let stream: AsyncStream<QueueItem>

        var body: some View {
            Color.clear
                .frame(width: 1, height: 1)
                .translationTask(state.configuration) { @Sendable session in
                    for await item in stream {
                        switch item {
                        case let .translate(text, continuation):
                            do {
                                let response = try await session.translate(text)
                                continuation.resume(returning: response.targetText)
                            } catch {
                                continuation.resume(throwing: error)
                            }
                        case .prepareDownload:
                            try? await session.prepareTranslation()
                        }
                    }
                }
        }
    }

    private let defaults: UserDefaults
    private let hostState = HostState()
    private let window: NSWindow
    private let stream: AsyncStream<QueueItem>
    private let continuation: AsyncStream<QueueItem>.Continuation
    private var currentPair: (source: TranslationTarget, target: TranslationTarget)?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        var streamContinuation: AsyncStream<QueueItem>.Continuation!
        stream = AsyncStream { streamContinuation = $0 }
        continuation = streamContinuation

        window = NSWindow(
            contentRect: NSRect(x: -10_000, y: -10_000, width: 1, height: 1),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.level = NSWindow.Level(rawValue: Int(NSWindow.Level.normal.rawValue) - 1_000)
        window.alphaValue = 0
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.isExcludedFromWindowsMenu = true
        window.collectionBehavior = [.transient, .ignoresCycle]

        let hostingView = NSHostingView(rootView: HostView(state: hostState, stream: stream))
        hostingView.frame = NSRect(x: 0, y: 0, width: 1, height: 1)
        window.contentView = hostingView
        window.orderFrontRegardless()
    }

    func availability(target: TranslationTarget) async -> TranslatorAvailability {
        let source = sourceLanguage(for: target)
        let status = await LanguageAvailability().status(
            from: Locale.Language(identifier: source.rawValue),
            to: Locale.Language(identifier: target.rawValue)
        )
        switch status {
        case .installed:
            return .ready
        case .supported:
            // Kick off the system download prompt proactively so the
            // "Download…" row the provider shows is informational — the
            // user doesn't need a second action to start the download.
            await requestDownload(target: target)
            return .needsDownload
        case .unsupported:
            return .unsupported
        @unknown default:
            return .unsupported
        }
    }

    func translate(_ text: String, to target: TranslationTarget) async throws -> String {
        let source = sourceLanguage(for: target)
        ensureConfiguration(source: source, target: target)
        return try await withCheckedThrowingContinuation { continuation in
            self.continuation.yield(.translate(text: text, continuation: continuation))
        }
    }

    func requestDownload(target: TranslationTarget) async {
        let source = sourceLanguage(for: target)
        ensureConfiguration(source: source, target: target)
        continuation.yield(.prepareDownload)
    }

    /// Our supported pairing is always {English, the configured Chinese
    /// variant}; given one side, the other is implied.
    private func sourceLanguage(for target: TranslationTarget) -> TranslationTarget {
        target == .english ? SettingsModel.storedChineseVariant(in: defaults) : .english
    }

    private func ensureConfiguration(source: TranslationTarget, target: TranslationTarget) {
        if let currentPair, currentPair.source == source, currentPair.target == target {
            return
        }
        currentPair = (source, target)
        hostState.configuration = TranslationSession.Configuration(
            source: Locale.Language(identifier: source.rawValue),
            target: Locale.Language(identifier: target.rawValue)
        )
    }
}
