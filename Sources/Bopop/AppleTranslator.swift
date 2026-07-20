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
final class AppleTranslator: NSObject, Translator, NSWindowDelegate {
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

    /// Hosts its own, deliberately separate `TranslationSession` purely to
    /// drive `prepareTranslation()` for `presentDownloadFlow()`'s visible
    /// window — NOT one of the four immortal `HostView` sessions above.
    /// Reusing one of those would tie this one-shot download UI's
    /// lifetime to the app's permanent translate plumbing for no benefit,
    /// and this session's whole point is to live inside a window the
    /// user can actually see, unlike theirs.
    private struct DownloadProgressView: View {
        let configuration: TranslationSession.Configuration
        let onSettled: @Sendable () -> Void

        @State private var statusText = "Waiting for download approval…"

        var body: some View {
            VStack(spacing: 16) {
                Text("Chinese ⇄ English Translation")
                    .font(.headline)
                // Apple's Translation framework exposes no byte-level
                // download-progress API for on-device language packs —
                // this indeterminate spinner plus the status text below
                // IS the progress feedback available to us.
                ProgressView()
                    .progressViewStyle(.circular)
                Text(statusText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(24)
            .frame(width: 380, height: 150)
            .translationTask(configuration) { @Sendable session in
                do {
                    try await session.prepareTranslation()
                } catch {
                    // User declined the download (or some other failure) —
                    // either way, there's nothing left to wait for.
                }
                onSettled()
            }
            .task {
                // No event distinguishes "the user is looking at the
                // system's consent sheet" from "bytes are downloading" —
                // both happen inside the single prepareTranslation() await
                // above — so this flips the status text once this view's
                // tasks are underway, the closest observable proxy we have.
                statusText = "Downloading language pack…"
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
    /// Guards `presentDownloadFlow()` against double-presentation: once a
    /// pair's visible download window is showing, a repeated Return on the
    /// "Download…" row brings the existing window forward instead of
    /// opening a second one. (This used to dedupe a proactive
    /// `requestDownload` call made from `availability()` — removed; see
    /// that method for why.)
    private var downloadRequested: Set<SessionPair> = []
    /// The single visible download-progress window, if one is currently
    /// showing — `presentDownloadFlow()` allows only one at a time.
    private var downloadWindow: NSWindow?
    /// Which pair `downloadWindow`/`downloadPollingTask` belong to, so
    /// `windowWillClose(_:)` and the completion/poll paths in
    /// `presentDownloadFlow()` know what to clear from `downloadRequested`
    /// when the flow ends.
    private var downloadPair: SessionPair?
    /// Belt-and-braces poll (see `presentDownloadFlow()`) that closes the
    /// download window once `LanguageAvailability` reports both directions
    /// of the pair installed, in case `prepareTranslation()`'s own
    /// completion is ever missed.
    private var downloadPollingTask: Task<Void, Never>?

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

        super.init()
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
            // Deliberately NOT kicking off a download here. prepareTranslation()
            // presents the system's download-consent sheet attached to whatever
            // window hosts the session that requested it — and every session
            // reachable from this method lives in the permanently offscreen,
            // alpha-0 host window above, so the sheet would render but never be
            // visible or approvable. That was the original bug: pressing Return
            // on the "Download…" row appeared to do nothing because the consent
            // sheet was there, just unseeable. The row's action now routes to
            // `presentDownloadFlow()`, which hosts a real, visible window for
            // exactly this purpose — see that method.
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

    /// Presents a small, real, titled window that hosts the on-device
    /// language-pack download/consent flow for {English, the configured
    /// Chinese variant}. This is the actual fix for the invisible-sheet
    /// bug: `prepareTranslation()`'s system consent sheet attaches to
    /// whatever window hosts its session, so that session has to live
    /// somewhere the user can see and interact with — unlike the four
    /// immortal sessions above, which stay in the permanently offscreen,
    /// alpha-0 window and exist only to keep `translate()` fast once a
    /// pair is already installed.
    ///
    /// Idempotent while a flow is already in progress for the pair:
    /// repeated Returns on the "Download…" row bring the existing window
    /// forward instead of presenting a second one.
    func presentDownloadFlow() {
        let target = SettingsModel.storedChineseVariant(in: defaults)
        let pair = SessionPair(source: .english, target: target)

        guard downloadPair != pair else {
            downloadWindow?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        guard !downloadRequested.contains(pair) else {
            return
        }
        downloadRequested.insert(pair)
        downloadPair = pair

        let configuration = TranslationSession.Configuration(
            source: Locale.Language(identifier: pair.source.rawValue),
            target: Locale.Language(identifier: pair.target.rawValue)
        )

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 380, height: 150),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Chinese ⇄ English Translation"
        window.level = .floating
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()

        let hostingView = NSHostingView(
            rootView: DownloadProgressView(configuration: configuration) { [weak self] in
                Task { @MainActor in
                    self?.handleDownloadSettled(for: pair)
                }
            }
        )
        hostingView.frame = NSRect(x: 0, y: 0, width: 380, height: 150)
        window.contentView = hostingView

        downloadWindow = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        startPollingAvailability(for: pair)
    }

    /// Belt-and-braces alongside `DownloadProgressView`'s own
    /// `prepareTranslation()` completion: closes the download window the
    /// moment `LanguageAvailability` reports BOTH directions of the pair
    /// as `.installed`, in case that completion callback is ever missed.
    /// There is no public byte-level progress API to poll instead — this,
    /// plus the indeterminate spinner/status text in
    /// `DownloadProgressView`, is the extent of the progress feedback the
    /// framework allows.
    private func startPollingAvailability(for pair: SessionPair) {
        downloadPollingTask?.cancel()
        downloadPollingTask = Task { [weak self] in
            let availability = LanguageAvailability()
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                guard !Task.isCancelled, let self else {
                    return
                }
                let forward = await availability.status(
                    from: Locale.Language(identifier: pair.source.rawValue),
                    to: Locale.Language(identifier: pair.target.rawValue)
                )
                let backward = await availability.status(
                    from: Locale.Language(identifier: pair.target.rawValue),
                    to: Locale.Language(identifier: pair.source.rawValue)
                )
                if forward == .installed, backward == .installed {
                    self.handleDownloadSettled(for: pair)
                    return
                }
            }
        }
    }

    private func handleDownloadSettled(for pair: SessionPair) {
        guard downloadPair == pair else {
            return
        }
        downloadWindow?.close()
    }

    /// Single cleanup path for the download flow ending, whether it's
    /// `handleDownloadSettled` closing the window programmatically or the
    /// user clicking the window's own titlebar close button — both funnel
    /// through here via `NSWindow.close()` triggering this delegate call.
    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow, window === downloadWindow else {
            return
        }
        downloadPollingTask?.cancel()
        downloadPollingTask = nil
        if let pair = downloadPair {
            downloadRequested.remove(pair)
        }
        downloadPair = nil
        downloadWindow = nil
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
