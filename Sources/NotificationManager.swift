import Foundation
import UserNotifications

/// Thin wrapper over UNUserNotificationCenter. Safe to use only from a bundled,
/// signed `.app` — guards against a missing bundle identifier to avoid crashing
/// if ever run as a bare executable.
///
/// Also acts as the notification delegate so that clicking a notification opens the
/// originating session in the agent view (the `cwd` is round-tripped through `userInfo`).
final class NotificationManager: NSObject, UNUserNotificationCenterDelegate {
    private var authorized = false
    private var available: Bool { Bundle.main.bundleIdentifier != nil }

    /// userInfo keys carrying the session's working directory and host for click handling.
    private static let cwdKey = "cwd"
    private static let hostKey = "hostID"

    func requestAuthorization() {
        guard available else { return }
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        center.requestAuthorization(options: [.alert, .sound]) { [weak self] granted, _ in
            self?.authorized = granted
        }
    }

    func notify(title: String, body: String, id: String, cwd: String, hostID: String) {
        guard available else {
            print("[Claudette] \(title) — \(body)")
            return
        }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.userInfo = [Self.cwdKey: cwd, Self.hostKey: hostID]

        // Unique request per transition so repeats aren't coalesced away.
        let request = UNNotificationRequest(
            identifier: "\(id)-\(Date().timeIntervalSince1970)",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }

    // MARK: UNUserNotificationCenterDelegate

    /// Clicking the banner opens the session it was fired for.
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        let info = response.notification.request.content.userInfo
        if let cwd = info[Self.cwdKey] as? String {
            let hostID = info[Self.hostKey] as? String ?? Host.localID
            DispatchQueue.main.async { SessionLauncher.open(cwd: cwd, hostID: hostID) }
        }
        completionHandler()
    }

    /// Still show banners while Claudette is the active app.
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }
}
