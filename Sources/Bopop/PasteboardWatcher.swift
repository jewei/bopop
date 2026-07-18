import AppKit
import BopopKit

@MainActor
final class PasteboardWatcher {
    private static let concealedType = NSPasteboard.PasteboardType(
        "org.nspasteboard.ConcealedType"
    )
    private static let transientType = NSPasteboard.PasteboardType(
        "org.nspasteboard.TransientType"
    )

    private let store: ClipboardStore
    private let pasteboard: NSPasteboard
    private let interval: TimeInterval
    private var lastChangeCount = 0
    private var timer: Timer?

    init(
        store: ClipboardStore,
        pasteboard: NSPasteboard = .general,
        interval: TimeInterval = 0.5
    ) {
        self.store = store
        self.pasteboard = pasteboard
        self.interval = interval
    }

    func start() {
        lastChangeCount = pasteboard.changeCount
        timer?.invalidate()

        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.pollPasteboard()
            }
        }
        timer.tolerance = 0.2
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func pollPasteboard() {
        let changeCount = pasteboard.changeCount
        guard changeCount != lastChangeCount else {
            return
        }
        lastChangeCount = changeCount

        let types = pasteboard.types ?? []
        guard !types.contains(Self.concealedType),
              !types.contains(Self.transientType) else {
            return
        }
        guard let text = pasteboard.string(forType: .string) else {
            return
        }

        // Re-copying a history entry is deduplicated or promoted by the store.
        store.add(text)
    }
}
