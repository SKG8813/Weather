import Foundation
import UpslopeCore
import UserNotifications

/// Silent alerts only. We never ask for sound permission and never attach a sound.
enum Notifier {
    static var center: UNUserNotificationCenter { .current() }

    @discardableResult
    static func requestPermission() async -> Bool {
        (try? await center.requestAuthorization(options: [.alert, .badge])) ?? false
    }

    static func status() async -> UNAuthorizationStatus {
        await center.notificationSettings().authorizationStatus
    }

    static func apply(_ action: AlertAction) async {
        switch action {
        case .none:
            break
        case .post(let c), .replace(let c):
            // Same identifier replaces the delivered alert instead of stacking a new one.
            await deliver(id: c.id, title: c.title, body: c.body, thread: "nexthour")
        case .remove(let id):
            center.removeDeliveredNotifications(withIdentifiers: [id])
            center.removePendingNotificationRequests(withIdentifiers: [id])
        }
    }

    static func deliver(id: String, title: String, body: String, thread: String) async {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = nil
        content.interruptionLevel = .active
        content.threadIdentifier = thread
        let request = UNNotificationRequest(identifier: id, content: content, trigger: nil)
        try? await center.add(request)
    }
}
