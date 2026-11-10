import Foundation
import Observation
import UserNotifications
import AniworldKit

/// Plant lokale Streak-Erinnerungen für heute und die nächsten zwei Tage voraus, damit sie auch
/// ankommen, wenn die App nicht geöffnet wird. Wird bei jeder Änderung der Statistik, beim Öffnen
/// und beim Wechsel in den Hintergrund neu berechnet.
@MainActor
@Observable
final class StreakReminderScheduler {
    @ObservationIgnored private let stats: WatchStatsStore
    @ObservationIgnored private let settings: SettingsStore
    @ObservationIgnored private var token: NSObjectProtocol?
    @ObservationIgnored private var pending: Task<Void, Never>?

    private static let idPrefix = "streak.reminder."
    /// „Letzte Chance“-Erinnerung, wenn der Streak am Abend noch offen ist.
    private static let lastChanceMinutes = 22 * 60 + 30
    private static let daysAhead = 2

    init(stats: WatchStatsStore, settings: SettingsStore) {
        self.stats = stats
        self.settings = settings
        token = NotificationCenter.default.addObserver(forName: .watchStatsDidChange, object: nil,
                                                       queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.scheduleSoon() }
        }
    }

    /// Fasst schnelle Änderungen (z. B. Sync) zusammen.
    func scheduleSoon() {
        pending?.cancel()
        pending = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            guard !Task.isCancelled else { return }
            await self?.reschedule()
        }
    }

    func reschedule(now: Date = Date(), calendar: Calendar = .current) async {
        let center = UNUserNotificationCenter.current()
        let requests = await center.pendingNotificationRequests()
        let old = requests.map(\.identifier).filter { $0.hasPrefix(Self.idPrefix) }
        center.removePendingNotificationRequests(withIdentifiers: old)

        guard settings.streakReminders else { return }
        let auth = await center.notificationSettings().authorizationStatus
        guard auth == .authorized || auth == .provisional || auth == .ephemeral else { return }

        for reminder in Self.plan(streak: stats.streak(now: now, calendar: calendar), now: now,
                                  reminderMinutes: settings.streakReminderMinutes, calendar: calendar) {
            let content = UNMutableNotificationContent()
            content.title = reminder.title
            content.body = reminder.body
            content.sound = .default
            content.threadIdentifier = "streak"
            let comps = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: reminder.date)
            let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
            let request = UNNotificationRequest(identifier: Self.idPrefix + reminder.id, content: content,
                                                trigger: trigger)
            try? await center.add(request)
        }
    }

    struct Reminder: Equatable {
        var id: String
        var date: Date
        var title: String
        var body: String
    }

    /// Welche Erinnerungen ab `now` anstehen. Tage, die schon zählen, bekommen keine.
    static func plan(streak: WatchStreak, now: Date, reminderMinutes: Int,
                     calendar: Calendar) -> [Reminder] {
        let today = calendar.startOfDay(for: now)
        var result: [Reminder] = []
        for offset in 0...daysAhead {
            guard let day = calendar.date(byAdding: .day, value: offset, to: today) else { continue }
            // Länge des Streaks, der an diesem Tag auf dem Spiel steht (0 = keiner mehr).
            let alive: Int
            switch offset {
            case 0:
                if streak.todayDone { continue }
                alive = streak.current
            case 1:
                alive = streak.todayDone ? streak.current : 0
            default:
                alive = 0
            }
            func at(_ minutes: Int) -> Date? {
                calendar.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: day)
            }
            if let date = at(reminderMinutes), date > now {
                if alive > 0 {
                    result.append(Reminder(
                        id: "\(offset).main", date: date,
                        title: "🔥 Dein Streak wartet",
                        body: "\(alive) \(alive == 1 ? "Tag" : "Tage") am Stück – schau heute eine ganze Folge, damit er weiterläuft."))
                } else {
                    result.append(Reminder(
                        id: "\(offset).main", date: date,
                        title: "Zeit für eine Folge?",
                        body: "Schau heute eine ganze Folge und starte einen neuen Streak."))
                }
            }
            if alive > 0, reminderMinutes < lastChanceMinutes, let date = at(lastChanceMinutes), date > now {
                result.append(Reminder(
                    id: "\(offset).last", date: date,
                    title: "⏰ Letzte Chance für deinen Streak",
                    body: "Nur noch bis Mitternacht: Eine Folge rettet deinen \(alive)-Tage-Streak."))
            }
        }
        return result
    }
}

extension Notification.Name {
    /// Gepostet bei jeder Änderung der Watch-Statistik (lokal oder durch Sync).
    static let watchStatsDidChange = Notification.Name("aniworld.watchStatsDidChange")
}
