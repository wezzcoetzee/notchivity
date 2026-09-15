import AppKit
import NotchivityKit
import UserNotifications

/// Posts events to Notification Center. Only works from inside a .app bundle; the bare
/// SwiftPM binary has no bundle identifier and UNUserNotificationCenter would crash.
final class Notifier: NSObject, UNUserNotificationCenterDelegate {
    static let shared = Notifier()
    private var urls: [String: URL] = [:]

    var available: Bool { Bundle.main.bundleIdentifier != nil && Bundle.main.bundleURL.pathExtension == "app" }

    func requestAuthorization() {
        guard available else { return }
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    func post(_ event: Event) {
        guard available else { return }
        let content = UNMutableNotificationContent()
        content.title = event.headline
        if let detail = event.detail { content.body = detail }
        content.sound = event.tone == .bad ? .default : nil
        let id = event.id.uuidString
        if let url = event.url { urls[id] = url }
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: id, content: content, trigger: nil))
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        if let url = urls.removeValue(forKey: response.notification.request.identifier) {
            NSWorkspace.shared.open(url)
        }
        completionHandler()
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }
}
