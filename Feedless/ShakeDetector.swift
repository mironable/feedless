import UIKit

/// Sits in the responder chain (UIApplication's delegate) so a shake reaches it whatever has focus.
final class AppDelegate: UIResponder, UIApplicationDelegate {
    static let shakeNotification = Notification.Name("feedless.shake")

    override func motionEnded(_ motion: UIEvent.EventSubtype, with event: UIEvent?) {
        if motion == .motionShake {
            NotificationCenter.default.post(name: Self.shakeNotification, object: nil)
        }
    }
}
