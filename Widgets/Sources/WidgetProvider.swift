import SwiftUI
import WidgetKit

struct SnapshotEntry: TimelineEntry {
    let date: Date
    /// `nil`, wenn die App noch keine Daten geschrieben hat bzw. die App Group fehlt.
    let snapshot: WidgetSnapshot?
}

/// Gemeinsamer Provider für alle drei Widgets.
struct SnapshotProvider: TimelineProvider {
    func placeholder(in context: Context) -> SnapshotEntry {
        SnapshotEntry(date: Date(), snapshot: WidgetSampleData.snapshot())
    }

    func getSnapshot(in context: Context, completion: @escaping (SnapshotEntry) -> Void) {
        if context.isPreview {
            completion(SnapshotEntry(date: Date(), snapshot: WidgetSampleData.snapshot()))
        } else {
            let now = Date()
            completion(SnapshotEntry(date: now, snapshot: WidgetShared.loadSnapshot()?.adjusted(for: now)))
        }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SnapshotEntry>) -> Void) {
        let now = Date()
        let calendar = Calendar.current
        let loaded = WidgetShared.loadSnapshot()

        var entries = [SnapshotEntry(date: now, snapshot: loaded?.adjusted(for: now))]
        let midnightComponents = DateComponents(hour: 0, minute: 0, second: 5)
        if let midnight = calendar.nextDate(after: now, matching: midnightComponents, matchingPolicy: .nextTime) {
            entries.append(SnapshotEntry(date: midnight, snapshot: loaded?.adjusted(for: midnight)))
        }
        let nextHour = calendar.date(byAdding: .hour, value: 1, to: now) ?? now.addingTimeInterval(3600)
        completion(Timeline(entries: entries, policy: .after(nextHour)))
    }
}

extension WidgetSnapshot {
    /// Rechnet die Momentaufnahme auf den Darstellungszeitpunkt um (z. B. nach Mitternacht):
    /// Tage verschieben, "heute geschaut" zurücksetzen, Serie ggf. beenden, Wochen-/Monatswerte nullen.
    func adjusted(for date: Date, calendar: Calendar = .current) -> WidgetSnapshot {
        var copy = self
        let today = calendar.startOfDay(for: date)
        let written = calendar.startOfDay(for: generatedAt)
        let shift = calendar.dateComponents([.day], from: written, to: today).day ?? 0
        guard shift > 0 else { return copy }

        var days = streak.lastSevenDays
        for offset in stride(from: shift - 1, through: 0, by: -1) {
            let d = calendar.date(byAdding: .day, value: -offset, to: today) ?? today
            days.append(WidgetSnapshot.Day(date: d, done: false))
        }
        copy.streak.lastSevenDays = Array(days.suffix(7))

        // Abstand zwischen letztem geschauten Tag und heute: Serie lebt nur bei <= 1.
        let lastDoneOffset = streak.todayDone ? 0 : 1
        copy.streak.todayDone = false
        if streak.current > 0 && shift + lastDoneOffset > 1 {
            copy.streak.current = 0
        }
        var mondayCalendar = calendar
        mondayCalendar.firstWeekday = 2  // Woche Mo–So, wie in der App
        // Intervall der Schreib-Woche/-Monat: liegt `date` darin, gelten die Werte noch.
        if mondayCalendar.dateInterval(of: .weekOfYear, for: generatedAt)?.contains(date) != true {
            copy.week = WidgetSnapshot.Period()
        }
        if calendar.dateInterval(of: .month, for: generatedAt)?.contains(date) != true {
            copy.month = WidgetSnapshot.Period()
        }
        return copy
    }
}

/// Beispieldaten für Platzhalter und Widget-Galerie.
enum WidgetSampleData {
    static func snapshot() -> WidgetSnapshot {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        var s = WidgetSnapshot()
        s.streak.current = 12
        s.streak.longest = 21
        s.streak.todayDone = true
        let pattern = [true, true, false, true, true, true, true]
        s.streak.lastSevenDays = (0..<7).map { i in
            WidgetSnapshot.Day(date: calendar.date(byAdding: .day, value: i - 6, to: today) ?? today, done: pattern[i])
        }
        s.week.totalSeconds = 3 * 3600 + 20 * 60
        s.week.completedEpisodes = 9
        s.week.seriesCount = 4
        s.week.topSeriesTitle = "Attack on Titan"
        s.week.weekdaySeconds = [2400, 3600, 0, 1800, 2700, 1500, 0]
        s.month.totalSeconds = 14 * 3600 + 5 * 60
        s.month.completedEpisodes = 36
        s.month.seriesCount = 7
        s.month.topSeriesTitle = "Attack on Titan"
        s.month.weekdaySeconds = [9000, 11000, 6000, 7500, 8800, 5200, 3400]
        let now = Date()
        s.continueWatching = [
            WidgetSnapshot.ContinueItem(slug: "attack-on-titan", title: "Attack on Titan", episodeLabel: "S2 · F5",
                                        progress: 0.62, remainingSeconds: 9 * 60, updatedAt: now, coverFileName: nil),
            WidgetSnapshot.ContinueItem(slug: "demon-slayer", title: "Demon Slayer", episodeLabel: "S1 · F12",
                                        progress: 0.25, remainingSeconds: 18 * 60, updatedAt: now, coverFileName: nil),
            WidgetSnapshot.ContinueItem(slug: "one-piece", title: "One Piece", episodeLabel: "S1 · F3",
                                        progress: 0.8, remainingSeconds: 5 * 60, updatedAt: now, coverFileName: nil),
            WidgetSnapshot.ContinueItem(slug: "jujutsu-kaisen", title: "Jujutsu Kaisen", episodeLabel: "S1 · F7",
                                        progress: 1, remainingSeconds: 0, updatedAt: now, coverFileName: nil,
                                        isNextEpisode: true)
        ]
        return s
    }
}
