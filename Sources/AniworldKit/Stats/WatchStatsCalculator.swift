import Foundation

// MARK: - Result types

public struct SeriesStat: Identifiable, Hashable, Sendable {
    public var slug: String
    public var title: String
    public var coverURL: URL?
    public var seconds: Double
    /// 0...1 share of the total watch time.
    public var share: Double
    public var episodes: Int
    public var id: String { slug }
}

public struct ShareStat: Identifiable, Hashable, Sendable {
    public var name: String
    public var seconds: Double
    /// 0...1
    public var share: Double
    public var id: String { name }
}

public struct BingeStat: Hashable, Sendable {
    public var episodes: Int
    public var seconds: Double
    public var start: Date
}

public enum TimeOfDay: Int, CaseIterable, Hashable, Sendable {
    case morning, noon, evening, night

    public var title: String {
        switch self {
        case .morning: "Morgens"
        case .noon: "Mittags"
        case .evening: "Abends"
        case .night: "Nachts"
        }
    }

    public static func of(hour: Int) -> TimeOfDay {
        switch hour {
        case 5..<11: return .morning
        case 11..<17: return .noon
        case 17..<23: return .evening
        default: return .night
        }
    }
}

public struct WatchStats: Hashable, Sendable {
    public var hasData = false
    public var totalSeconds: Double = 0
    public var sessionCount = 0
    /// Distinct episodes watched (at least partly).
    public var episodeCount = 0
    /// Distinct episodes watched to the end.
    public var completedEpisodeCount = 0
    public var seriesCount = 0
    public var topSeries: [SeriesStat] = []
    public var topGenres: [ShareStat] = []
    public var languages: [ShareStat] = []
    public var averageSessionSeconds: Double = 0
    public var activeDays = 0
    public var averageEpisodesPerActiveDay: Double = 0
    public var longestBinge: BingeStat?
    /// Watch seconds per weekday, Monday first.
    public var weekdaySeconds: [Double] = Array(repeating: 0, count: 7)
    /// Index into `weekdaySeconds` (0 = Monday).
    public var mostActiveWeekday: Int?
    /// Watch seconds per `TimeOfDay` (in `allCases` order).
    public var timeOfDaySeconds: [Double] = Array(repeating: 0, count: 4)
    public var mostActiveTimeOfDay: TimeOfDay?
    public var longestStreakDays = 0
    /// 0...1
    public var completionRate: Double = 0
    public var skippedSeconds: Double = 0
    /// 0...1
    public var offlineShare: Double = 0
    public var newSeriesCount = 0
    public var previousTotalSeconds: Double?
    /// Relative change to the previous period (0.25 = +25 %); nil without comparison data.
    public var changeToPrevious: Double?
    public var funComparison: String?

    public static let weekdayNames = ["Montag", "Dienstag", "Mittwoch", "Donnerstag", "Freitag", "Samstag", "Sonntag"]
    public static let weekdayShortNames = ["Mo", "Di", "Mi", "Do", "Fr", "Sa", "So"]

    public var mostActiveWeekdayName: String? {
        mostActiveWeekday.map { WatchStats.weekdayNames[$0] }
    }
}

// MARK: - Calculator

/// Computes the statistics of a period from raw sessions. Pure and deterministic.
public struct WatchStatsCalculator {
    public var sessions: [WatchSession]
    public var interval: DateInterval
    public var calendar: Calendar
    public var seriesMeta: [String: SeriesMeta]
    public var previousInterval: DateInterval?

    /// A gap shorter than this keeps a binge chain together.
    public static let bingeGap: TimeInterval = 15 * 60

    public init(sessions: [WatchSession], interval: DateInterval, calendar: Calendar = .current,
                seriesMeta: [String: SeriesMeta] = [:], previousInterval: DateInterval? = nil) {
        self.sessions = sessions
        self.interval = interval
        self.calendar = calendar
        self.seriesMeta = seriesMeta
        self.previousInterval = previousInterval
    }

    private func contains(_ interval: DateInterval, _ date: Date) -> Bool {
        date >= interval.start && date < interval.end
    }

    /// Start of the earliest session (for the month picker).
    public static func firstDate(of sessions: [WatchSession]) -> Date? {
        sessions.map { $0.startedAt }.min()
    }

    private struct SeriesAcc {
        var title: String
        var cover: URL?
        var seconds: Double
        var episodes: Set<String>
        var latest: Date
    }

    private struct DayEpisode: Hashable {
        var day: Date
        var key: String
    }

    public func compute() -> WatchStats {
        var stats = WatchStats()
        let inPeriod: [WatchSession] = sessions
            .filter { contains(interval, $0.startedAt) && $0.watchedSeconds > 0 }
            .sorted { (a: WatchSession, b: WatchSession) -> Bool in
                a.startedAt != b.startedAt ? a.startedAt < b.startedAt : a.id < b.id
            }

        if let previousInterval {
            let prev: Double = sessions
                .filter { contains(previousInterval, $0.startedAt) }
                .reduce(0) { (acc: Double, s: WatchSession) -> Double in acc + s.watchedSeconds }
            stats.previousTotalSeconds = prev
        }

        guard !inPeriod.isEmpty else { return stats }
        stats.hasData = true

        let total: Double = inPeriod.reduce(0) { (acc: Double, s: WatchSession) -> Double in acc + s.watchedSeconds }
        stats.totalSeconds = total
        stats.sessionCount = inPeriod.count
        stats.averageSessionSeconds = total / Double(inPeriod.count)
        if let prev = stats.previousTotalSeconds, prev > 0 {
            stats.changeToPrevious = (total - prev) / prev
        }

        // Episodes
        var episodeKeys = Set<String>()
        var completedKeys = Set<String>()
        for s in inPeriod {
            episodeKeys.insert(s.episodeKey)
            if s.completed { completedKeys.insert(s.episodeKey) }
        }
        stats.episodeCount = episodeKeys.count
        stats.completedEpisodeCount = completedKeys.count
        stats.completionRate = episodeKeys.isEmpty ? 0 : Double(completedKeys.count) / Double(episodeKeys.count)

        // Series
        var bySeries: [String: SeriesAcc] = [:]
        for s in inPeriod {
            var acc: SeriesAcc = bySeries[s.seriesSlug]
                ?? SeriesAcc(title: s.seriesTitle, cover: s.coverURL, seconds: 0, episodes: [], latest: s.startedAt)
            acc.seconds += s.watchedSeconds
            acc.episodes.insert(s.episodeKey)
            if s.startedAt >= acc.latest {
                acc.latest = s.startedAt
                acc.title = s.seriesTitle
            }
            if let cover = s.coverURL { acc.cover = cover }
            bySeries[s.seriesSlug] = acc
        }
        stats.seriesCount = bySeries.count
        let ranked: [SeriesStat] = bySeries
            .map { (slug: String, acc: SeriesAcc) -> SeriesStat in
                SeriesStat(slug: slug, title: acc.title, coverURL: acc.cover, seconds: acc.seconds,
                           share: total > 0 ? acc.seconds / total : 0, episodes: acc.episodes.count)
            }
            .sorted { (a: SeriesStat, b: SeriesStat) -> Bool in
                a.seconds != b.seconds ? a.seconds > b.seconds : a.slug < b.slug
            }
        stats.topSeries = Array(ranked.prefix(5))

        // Genres: the time of a session is split evenly across the genres of its series.
        var genreSeconds: [String: Double] = [:]
        for s in inPeriod {
            let genres: [String] = seriesMeta[s.seriesSlug]?.genres ?? []
            guard !genres.isEmpty else { continue }
            let part = s.watchedSeconds / Double(genres.count)
            for g in genres { genreSeconds[g, default: 0] += part }
        }
        let genreTotal: Double = genreSeconds.values.reduce(0, +)
        stats.topGenres = genreSeconds
            .map { (name: String, seconds: Double) -> ShareStat in
                ShareStat(name: name, seconds: seconds, share: genreTotal > 0 ? seconds / genreTotal : 0)
            }
            .sorted { (a: ShareStat, b: ShareStat) -> Bool in
                a.seconds != b.seconds ? a.seconds > b.seconds : a.name < b.name
            }
            .prefix(5)
            .map { $0 }

        // Languages
        var langSeconds: [StreamLanguage: Double] = [:]
        for s in inPeriod {
            if let l = s.language { langSeconds[l, default: 0] += s.watchedSeconds }
        }
        let langTotal: Double = langSeconds.values.reduce(0, +)
        var langStats: [ShareStat] = []
        for l in StreamLanguage.allCases {
            guard let sec = langSeconds[l], sec > 0 else { continue }
            langStats.append(ShareStat(name: l.shortName, seconds: sec, share: langTotal > 0 ? sec / langTotal : 0))
        }
        stats.languages = langStats

        // Days, weekdays, time of day
        var days = Set<Date>()
        var dayEpisodes = Set<DayEpisode>()
        var weekday = Array(repeating: 0.0, count: 7)
        var tod = Array(repeating: 0.0, count: 4)
        for s in inPeriod {
            let day = calendar.startOfDay(for: s.startedAt)
            days.insert(day)
            dayEpisodes.insert(DayEpisode(day: day, key: s.episodeKey))
            let w = calendar.component(.weekday, from: s.startedAt) // 1 = Sunday
            weekday[(w + 5) % 7] += s.watchedSeconds
            let hour = calendar.component(.hour, from: s.startedAt)
            tod[TimeOfDay.of(hour: hour).rawValue] += s.watchedSeconds
        }
        stats.activeDays = days.count
        stats.averageEpisodesPerActiveDay = days.isEmpty ? 0 : Double(dayEpisodes.count) / Double(days.count)
        stats.weekdaySeconds = weekday
        if let maxW = weekday.max(), maxW > 0, let idx = weekday.firstIndex(of: maxW) { stats.mostActiveWeekday = idx }
        stats.timeOfDaySeconds = tod
        if let maxT = tod.max(), maxT > 0, let idx = tod.firstIndex(of: maxT) {
            stats.mostActiveTimeOfDay = TimeOfDay(rawValue: idx)
        }
        stats.longestStreakDays = longestStreak(days: days)
        stats.longestBinge = longestBinge(inPeriod)

        // Skips / offline
        stats.skippedSeconds = inPeriod.reduce(0) { (acc: Double, s: WatchSession) -> Double in acc + s.skippedSeconds }
        let offline: Double = inPeriod.filter { $0.wasOffline }
            .reduce(0) { (acc: Double, s: WatchSession) -> Double in acc + s.watchedSeconds }
        stats.offlineShare = total > 0 ? offline / total : 0

        // New series: the very first session of the series lies in this period.
        var firstStart: [String: Date] = [:]
        for s in sessions {
            if let current = firstStart[s.seriesSlug] {
                if s.startedAt < current { firstStart[s.seriesSlug] = s.startedAt }
            } else {
                firstStart[s.seriesSlug] = s.startedAt
            }
        }
        stats.newSeriesCount = firstStart.values.filter { contains(interval, $0) }.count

        stats.funComparison = Self.funComparison(totalSeconds: total)
        return stats
    }

    private func longestStreak(days: Set<Date>) -> Int {
        let sorted: [Date] = days.sorted()
        guard var previous = sorted.first else { return 0 }
        var best = 1
        var current = 1
        for day in sorted.dropFirst() {
            if let next = calendar.date(byAdding: .day, value: 1, to: previous), next == day {
                current += 1
            } else {
                current = 1
            }
            best = max(best, current)
            previous = day
        }
        return best
    }

    /// Longest chain of sessions where each one starts less than `bingeGap` after the previous ended.
    private func longestBinge(_ sorted: [WatchSession]) -> BingeStat? {
        var best: BingeStat?
        var keys = Set<String>()
        var seconds = 0.0
        var start: Date?
        var chainEnd: Date = .distantPast

        func close() {
            guard let begin = start, !keys.isEmpty else { return }
            let candidate = BingeStat(episodes: keys.count, seconds: seconds, start: begin)
            if let current = best {
                if candidate.episodes > current.episodes
                    || (candidate.episodes == current.episodes && candidate.seconds > current.seconds) {
                    best = candidate
                }
            } else {
                best = candidate
            }
        }

        for s in sorted {
            if start != nil, s.startedAt.timeIntervalSince(chainEnd) < Self.bingeGap {
                // same chain
            } else {
                close()
                keys = []
                seconds = 0
                start = s.startedAt
                chainEnd = .distantPast
            }
            keys.insert(s.episodeKey)
            seconds += s.watchedSeconds
            chainEnd = max(chainEnd, s.endedAt)
        }
        close()
        return best
    }

    /// A playful comparison for the total watch time (nil when there is almost nothing to compare).
    public static func funComparison(totalSeconds: Double) -> String? {
        let hours = totalSeconds / 3600
        let lotr = hours / 11.4 // extended trilogy
        if lotr >= 1 {
            let n = Double(Int(lotr * 10)) / 10
            let text = n == n.rounded() ? String(Int(n)) : String(format: "%.1f", n).replacingOccurrences(of: ".", with: ",")
            return "Das entspricht \(text)-mal der Herr-der-Ringe-Trilogie (Extended Edition)."
        }
        let movies = hours / 2
        if movies >= 1 {
            let n = Int(movies)
            return n == 1 ? "Das entspricht einem Film à 2 Stunden." : "Das entspricht \(n) Filmen à 2 Stunden."
        }
        let episodes = totalSeconds / (24 * 60)
        if episodes >= 1 {
            let n = Int(episodes)
            return n == 1 ? "Das entspricht einer Anime-Folge à 24 Minuten."
                          : "Das entspricht \(n) Anime-Folgen à 24 Minuten."
        }
        return nil
    }
}

// MARK: - Periods

/// A selectable period of the statistics screen.
public enum StatsPeriod: Hashable, Sendable, Identifiable {
    case month(year: Int, month: Int)
    case year(Int)
    case all

    public static let monthNames = ["Januar", "Februar", "März", "April", "Mai", "Juni", "Juli",
                                    "August", "September", "Oktober", "November", "Dezember"]

    public var id: String {
        switch self {
        case let .month(y, m): return "m-\(y)-\(m)"
        case let .year(y): return "y-\(y)"
        case .all: return "all"
        }
    }

    public var title: String {
        switch self {
        case let .month(y, m): return "\(StatsPeriod.monthNames[min(max(m, 1), 12) - 1]) \(y)"
        case let .year(y): return String(y)
        case .all: return "Gesamt"
        }
    }

    /// Only the month name ("Oktober").
    public var monthName: String? {
        if case let .month(_, m) = self { return StatsPeriod.monthNames[min(max(m, 1), 12) - 1] }
        return nil
    }

    public static func month(containing date: Date, calendar: Calendar) -> StatsPeriod {
        let c = calendar.dateComponents([.year, .month], from: date)
        return .month(year: c.year ?? 1970, month: c.month ?? 1)
    }

    public func interval(calendar: Calendar) -> DateInterval {
        switch self {
        case let .month(y, m):
            let start = calendar.date(from: DateComponents(year: y, month: m, day: 1)) ?? Date.distantPast
            let end = calendar.date(byAdding: .month, value: 1, to: start) ?? start
            return DateInterval(start: start, end: end)
        case let .year(y):
            let start = calendar.date(from: DateComponents(year: y, month: 1, day: 1)) ?? Date.distantPast
            let end = calendar.date(byAdding: .year, value: 1, to: start) ?? start
            return DateInterval(start: start, end: end)
        case .all:
            return DateInterval(start: Date.distantPast, end: Date.distantFuture)
        }
    }

    public func previousInterval(calendar: Calendar) -> DateInterval? {
        switch self {
        case let .month(y, m):
            let start = calendar.date(from: DateComponents(year: y, month: m, day: 1)) ?? Date.distantPast
            guard let prevStart = calendar.date(byAdding: .month, value: -1, to: start) else { return nil }
            return DateInterval(start: prevStart, end: start)
        case let .year(y):
            let start = calendar.date(from: DateComponents(year: y, month: 1, day: 1)) ?? Date.distantPast
            guard let prevStart = calendar.date(byAdding: .year, value: -1, to: start) else { return nil }
            return DateInterval(start: prevStart, end: start)
        case .all:
            return nil
        }
    }

    /// The month before `date`'s month.
    public static func previousMonth(of date: Date, calendar: Calendar) -> StatsPeriod {
        let startOfMonth: Date = calendar.date(from: calendar.dateComponents([.year, .month], from: date)) ?? date
        let prev: Date = calendar.date(byAdding: .month, value: -1, to: startOfMonth) ?? startOfMonth
        return month(containing: prev, calendar: calendar)
    }

    /// Months from `now` back to the first data (newest first, at most `limit`).
    public static func availableMonths(firstDate: Date?, now: Date, calendar: Calendar, limit: Int = 25) -> [StatsPeriod] {
        var result: [StatsPeriod] = [month(containing: now, calendar: calendar)]
        guard let firstDate else { return result }
        let first = month(containing: firstDate, calendar: calendar)
        var cursor: Date = now
        while result.count < limit, result.last != first {
            let startOfMonth: Date = calendar.date(from: calendar.dateComponents([.year, .month], from: cursor)) ?? cursor
            guard let prev = calendar.date(byAdding: .month, value: -1, to: startOfMonth) else { break }
            cursor = prev
            let p = month(containing: prev, calendar: calendar)
            if result.contains(p) { break }
            result.append(p)
        }
        return result
    }
}
