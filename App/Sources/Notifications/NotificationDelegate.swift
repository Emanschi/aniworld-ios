import Foundation
import UserNotifications
import AniworldKit

/// Zeigt Mitteilungen auch im Vordergrund an und meldet Taps auf eine Serie zurück.
@MainActor
final class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    /// Wird auf dem Main Actor aufgerufen, wenn der Nutzer eine „Neue Folge“-Mitteilung antippt.
    var onOpenSeries: ((SeriesSummary) -> Void)?

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .list, .sound])
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let info: [AnyHashable: Any] = response.notification.request.content.userInfo
        let slug: String? = info["slug"] as? String
        let title: String = (info["title"] as? String) ?? ""
        let urlString: String? = info["url"] as? String
        if let slug = slug, let urlString = urlString, let url = URL(string: urlString) {
            let summary = SeriesSummary(slug: slug, title: title, url: url)
            Task { @MainActor in
                self.onOpenSeries?(summary)
            }
        }
        completionHandler()
    }
}
