import Foundation
import Testing
@testable import Bopop

@MainActor
@Test
func notificationTokenRemovesObserverWhenReleased() {
    let center = NotificationCenter()
    let name = Notification.Name("NotificationTokenTests.event")
    var deliveries = 0
    var token: NotificationToken? = NotificationToken(
        center: center,
        name: name
    ) {
        deliveries += 1
    }

    #expect(token != nil)
    center.post(name: name, object: nil)
    #expect(deliveries == 1)

    token = nil
    center.post(name: name, object: nil)
    #expect(deliveries == 1)
}
