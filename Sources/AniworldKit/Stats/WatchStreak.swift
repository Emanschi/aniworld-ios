import Foundation

/// Daily streak (Duolingo-style): a day counts only if at least one episode was watched completely.
public struct WatchStreak: Hashable, Sendable {
    /// Consecutive counted days up to today (or up to yesterday while today is still open).
    public var current = 0
    public var longest = 0
    /// Today already counts.
    public var todayDone = false
    /// The streak is alive but today has no complete episode yet.
    public var atRisk: Bool { current > 0 && !todayDone }
    /// The last 7 days, oldest first, the last element is today.
    public var lastSevenDays: [StreakDay] = []

    public init() {}

    public struct StreakDay: Hashable, Sendable {
        public var date: Date
        public var done: Bool
    }

    /// Days with a completed episode count by the day the session ended.
    public static func compute(sessions: [WatchSession], now: Date = Date(),
                               calendar: Calendar = .current) -> WatchStreak {
        var days = Set<Date>()
        for session in sessions where session.completed {
            days.insert(calendar.startOfDay(for: session.endedAt))
        }
        let today: Date = calendar.startOfDay(for: now)
        var streak = WatchStreak()
        streak.todayDone = days.contains(today)

        // Current streak: walk back from today (or yesterday if today is still open).
        var cursor: Date? = streak.todayDone ? today : calendar.date(byAdding: .day, value: -1, to: today)
        while let day = cursor, days.contains(day) {
            streak.current += 1
            cursor = calendar.date(byAdding: .day, value: -1, to: day)
        }

        // Longest streak over all days.
        var best = 0
        var run = 0
        var previous: Date?
        for day in days.sorted() {
            if let previous, calendar.date(byAdding: .day, value: 1, to: previous) == day {
                run += 1
            } else {
                run = 1
            }
            best = max(best, run)
            previous = day
        }
        streak.longest = max(best, streak.current)

        var week: [StreakDay] = []
        for offset in stride(from: -6, through: 0, by: 1) {
            if let day = calendar.date(byAdding: .day, value: offset, to: today) {
                week.append(StreakDay(date: day, done: days.contains(day)))
            }
        }
        streak.lastSevenDays = week
        return streak
    }
}
