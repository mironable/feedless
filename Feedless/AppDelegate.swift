import UIKit
import UserNotifications

/// Sits in the responder chain (UIApplication's delegate) so a shake reaches it whatever has focus.
final class AppDelegate: UIResponder, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    static let shakeNotification = Notification.Name("feedless.shake")
    static let openURLNotification = Notification.Name("feedless.openURL")
    static let openSettingsNotification = Notification.Name("feedless.openSettings")

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        BackgroundRefresh.register()
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    override func motionEnded(_ motion: UIEvent.EventSubtype, with event: UIEvent?) {
        if motion == .motionShake {
            NotificationCenter.default.post(name: Self.shakeNotification, object: nil)
        }
    }

    /// A tapped DM alert opens its thread in the web view.
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        guard let string = response.notification.request.content.userInfo["url"] as? String,
              let url = URL(string: string) else { return }
        NotificationCenter.default.post(name: Self.openURLNotification, object: url)
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound, .badge]
    }
}
