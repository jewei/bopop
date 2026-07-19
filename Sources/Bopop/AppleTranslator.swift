import AppKit
import BopopKit
import SwiftUI
import Translation

/// `Translator` backed by Apple's on-device `Translation` framework.
///
/// `TranslationSession` can only be obtained through the SwiftUI
/// `.translationTask(_:action:)` view modifier, so this class hosts four
/// hidden 1×1 `NSHostingView`s — one per supported language pair, stacked
/// inside a single persistent, never-visible offscreen window (alpha 0,
/// level well below `.normal`) that lives for the app's entire lifetime.
///
/// Each host view's `.translationTask` is given a *constant*
/// `TranslationSession.Configuration` fixed at init and never mutated
/// afterward. This matters: `.translationTask(configuration:)` cancels and
/// restarts its `action` task whenever the configuration value changes,
/// and the `for await item in stream` drain loop inside that task dies
/// with it — since `AsyncStream` is single-consumption, any later
/// `translate()` call yielding into a now-abandoned stream would hang
/// forever (its `CheckedContinuation` never resumed). Pinning one
/// immortal session per language pair, instead of reconfiguring a single
/// shared session when the direction flips, guarantees each stream has
/// exactly one consumer for the app's whole lifetime: no task restarts,
/// no dropped continuations, no leaks.
///
/// Requests from `translate(_:to:)`/`requestDownload(target:)` are routed
/// by `(source, target)` into the matching pair's `AsyncStream`; the
/// corresponding host view's long-running task drains its own stream and
/// fulfills each request with `session.translate(_:)` /
/// `session.prepareTranslation()`.
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

    private struct SessionPair: Hashable {
        let source: TranslationTarget
        let target: TranslationTarget
    }

    /// The drain loop lives directly inside the `.translationTask` closure
    /// (rather than being handed off to a separate `AppleTranslator`
    /// method) so `TranslationSession` — which is not `Sendable` — never
    /// has to cross an isolation boundary; only the `Sendable` `stream`
    /// and its `Sendable` `QueueItem`s do. `configuration` is a plain
    /// `let`: it is set once when the view is built and never changes, so
    /// `.translationTask` never sees a new configuration value and never
    /// restarts this task.
    private struct HostView: View {
        let configuration: TranslationSession.Configuration
        let stream: AsyncStream<QueueItem>

        var body: some View {
            Color.clear
                .frame(width: 1, height: 1)
                .translationTask(configuration) { @Sendable session in
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

    private struct HostsContainerView: View {
        let hosts: [HostView]

        var body: some View {
            VStack(spacing: 0) {
                ForEach(hosts.indices, id: \.self) { index in
                    hosts[index]
                }
            }
        }
    }

    /// English⇄Simplified and English⇄Traditional, both directions each —
    /// the only pairs `TranslationDirection.target(for:chineseVariant:)`
    /// can ever produce.
    private static let allPairs: [SessionPair] = [
        SessionPair(source: .english, target: .chineseSimplified),
        SessionPair(source: .chineseSimplified, target: .english),
        SessionPair(source: .english, target: .chineseTraditional),
        SessionPair(source: .chineseTraditional, target: .english)
    ]

    private let defaults: UserDefaults
    private let window: NSWindow
    private var continuations: [SessionPair: AsyncStream<QueueItem>.Continuation] = [:]
    /// Download prompts are deduped per pair per app run here — creating a
    /// session for an uninstalled pair does NOT itself prompt (only
    /// `prepareTranslation()`/`translate()` do), so this only needs to
    /// guard those two call sites, not session construction above.
    private var downloadRequested: Set<SessionPair> = []

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        window = NSWindow(
            contentRect: NSRect(
                x: -10_000,
                y: -10_000,
                width: 1,
                height: CGFloat(Self.allPairs.count)
            ),
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

        var continuations: [SessionPair: AsyncStream<QueueItem>.Continuation] = [:]
        let hosts: [HostView] = Self.allPairs.map { pair in
            var pairContinuation: AsyncStream<QueueItem>.Continuation!
            let pairStream = AsyncStream<QueueItem> { pairContinuation = $0 }
            continuations[pair] = pairContinuation
            let configuration = TranslationSession.Configuration(
                source: Locale.Language(identifier: pair.source.rawValue),
                target: Locale.Language(identifier: pair.target.rawValue)
            )
            return HostView(configuration: configuration, stream: pairStream)
        }
        self.continuations = continuations

        let hostingView = NSHostingView(rootView: HostsContainerView(hosts: hosts))
        hostingView.frame = NSRect(x: 0, y: 0, width: 1, height: CGFloat(hosts.count))
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
            // requestDownload dedupes per pair per run, so repeated
            // keystrokes (TranslationProvider calls availability on every
            // one) don't re-prompt after the user has already seen it.
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
        let pair = SessionPair(source: source, target: target)
        guard let continuation = continuations[pair] else {
            throw TranslatorPairError.unsupportedPair
        }
        return try await withCheckedThrowingContinuation { resultContinuation in
            continuation.yield(.translate(text: text, continuation: resultContinuation))
        }
    }

    func requestDownload(target: TranslationTarget) async {
        let source = sourceLanguage(for: target)
        let pair = SessionPair(source: source, target: target)
        guard !downloadRequested.contains(pair) else {
            return
        }
        downloadRequested.insert(pair)
        continuations[pair]?.yield(.prepareDownload)
    }

    /// Our supported pairing is always {English, the configured Chinese
    /// variant}; given one side, the other is implied.
    private func sourceLanguage(for target: TranslationTarget) -> TranslationTarget {
        target == .english ? SettingsModel.storedChineseVariant(in: defaults) : .english
    }
}

private enum TranslatorPairError: Error {
    case unsupportedPair
}
