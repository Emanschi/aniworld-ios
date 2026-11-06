import Foundation

/// Data the app hands to the home-screen widgets.
///
/// Compiled into BOTH targets (app + widget extension). The app writes it as JSON into the
/// shared App Group container, the widget only reads it. This file is the contract between both
/// sides: adding fields with defaults is fine, renaming/removing is not.
struct WidgetSnapshot: Codable, Hashable, Sendable {
    static let currentVersion = 1

    var version: Int = WidgetSnapshot.currentVersion
    /// When the app wrote this snapshot.
    var generatedAt: Date = Date()

    var streak = Streak()
    var week = Period()
    var month = Period()
    /// Most recent unfinished entries from "Weiterschauen", newest first (max. 4).
    var continueWatching: [ContinueItem] = []

    init() {}

    struct Streak: Codable, Hashable, Sendable {
        var current = 0
        var longest = 0
        var todayDone = false
        /// Last 7 days, oldest first; last element is today.
        var lastSevenDays: [Day] = []

        var atRisk: Bool { current > 0 && !todayDone }

        init() {}
    }

    struct Day: Codable, Hashable, Sendable {
        var date: Date
        var done: Bool
    }

    /// Aggregated statistics of a period (this week / this month).
    struct Period: Codable, Hashable, Sendable {
        var totalSeconds: Double = 0
        var completedEpisodes = 0
        var seriesCount = 0
        /// Title of the most watched series in the period.
        var topSeriesTitle: String?
        /// Watch seconds per weekday, Monday first (7 values).
        var weekdaySeconds: [Double] = Array(repeating: 0, count: 7)

        init() {}
    }

    struct ContinueItem: Codable, Hashable, Sendable, Identifiable {
        var slug: String
        var title: String
        /// e.g. "S1 · F5"
        var episodeLabel: String
        /// 0...1
        var progress: Double
        var remainingSeconds: Double
        var updatedAt: Date
        /// File name of a small JPEG cover inside `WidgetShared.coversDirectory` (nil = no cover).
        var coverFileName: String?
        /// The last episode was watched to the end: the widget shows "Nächste Folge" instead of
        /// progress / remaining time (`episodeLabel` names the finished episode).
        var isNextEpisode: Bool = false

        var id: String { slug }
    }
}

/// Shared constants and file locations used by app and widget.
enum WidgetShared {
    static let appGroupID = "group.com.aniworldios.app"
    static let urlScheme = "aniworld"

    /// Widget kinds (WidgetConfiguration `kind`), used for targeted reloads.
    enum Kind {
        static let streak = "StreakWidget"
        static let continueWatching = "ContinueWatchingWidget"
        static let stats = "StatsWidget"
    }

    /// `nil` when the App Group is not available (e.g. sideloaded without the entitlement).
    static var containerURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID)
    }

    static var snapshotURL: URL? { containerURL?.appendingPathComponent("widget-snapshot.json") }

    static var coversDirectory: URL? { containerURL?.appendingPathComponent("WidgetCovers", isDirectory: true) }

    static func loadSnapshot() -> WidgetSnapshot? {
        guard let url = snapshotURL, let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(WidgetSnapshot.self, from: data)
    }

    static func encode(_ snapshot: WidgetSnapshot) -> Data? {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return try? encoder.encode(snapshot)
    }

    // MARK: Deep links (handled by the app's RootView)

    /// aniworld://series/<slug>  → opens the series page.
    static func seriesURL(slug: String) -> URL {
        var c = URLComponents()
        c.scheme = urlScheme
        c.host = "series"
        c.path = "/" + slug
        return c.url ?? URL(string: "\(urlScheme)://home")!
    }

    /// aniworld://stats  → opens the statistics screen.
    static let statsURL = URL(string: "\(urlScheme)://stats")!

    /// aniworld://home
    static let homeURL = URL(string: "\(urlScheme)://home")!
}
