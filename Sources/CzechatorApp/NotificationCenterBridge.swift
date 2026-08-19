import AppKit
import UserNotifications

/// Thin wrapper so the model does not deal with the notification framework
/// directly. Clicking a notification routes back through `onActivate`.
///
/// Notifications are the secondary channel: an ad-hoc signed bundle may not be
/// allowed to post them at all, so the menu bar badge remains the primary way
/// the user learns something went wrong.
@MainActor
final class NotificationCenterBridge: NSObject, UNUserNotificationCenterDelegate {

    var onActivate: (@MainActor () -> Void)?
    private var authorized = false

    func requestAuthorization() {
        UNUserNotificationCenter.current().delegate = self
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert]) { granted, _ in
            Task { @MainActor in self.authorized = granted }
        }
    }

    func post(title: String, body: String) {
        guard authorized else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        await MainActor.run { self.onActivate?() }
    }
}
