import Foundation

@MainActor
final class NotificationToken {
    private let center: NotificationCenter
    private let observer: NSObjectProtocol

    init(
        center: NotificationCenter = .default,
        name: Notification.Name,
        object: Any? = nil,
        handler: @escaping @MainActor () -> Void
    ) {
        self.center = center
        observer = center.addObserver(
            forName: name,
            object: object,
            queue: .main
        ) { _ in
            MainActor.assumeIsolated {
                handler()
            }
        }
    }

    isolated deinit {
        center.removeObserver(observer)
    }
}
