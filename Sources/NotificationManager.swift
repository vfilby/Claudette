import Foundation
import UserNotifications

/// Thin wrapper over UNUserNotificationCenter. Safe to use only from a bundled,
/// signed `.app` — guards against a missing bundle identifier to avoid crashing
/// if ever run as a bare executable.
final class NotificationManager {
    private var authorized = false
    private var available: Bool { Bundle.main.bundleIdentifier != nil }

    func requestAuthorization() {
        guard available else { return }
        UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound]) { [weak self] granted, _ in
                self?.authorized = granted
            }
    }

    func notify(title: String, body: String, id: String) {
        guard available else {
            print("[Claudette] \(title) — \(body)")
            return
        }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        // Unique request per transition so repeats aren't coalesced away.
        let request = UNNotificationRequest(
            identifier: "\(id)-\(Date().timeIntervalSince1970)",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }
}
