import Foundation

/// Data the app hands to the home-screen widgets.
///
/// Compiled into BOTH targets (app + widget extension). The app writes it as JSON into the
/// shared App Group container, the widget only reads it. This file is the contract between both
/// sides: adding fields with defaults is fine, renaming/removing is not.
///
/// Decoding is tolerant: every field with a default is read with `decodeIfPresent`, so JSON files
/// written by an older app version (missing newer fields) still load. Only `Day.date`/`Day.done`
/// and `ContinueItem.slug`/`ContinueItem.title` are required. New fields MUST get a default and
/// be added to the matching `init(from:)` below. Encoding stays synthesized.
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

    enum CodingKeys: String, CodingKey {
        case version, generatedAt, streak, week, month, continueWatching
    }

    struct Streak: Codable, Hashable, Sendable {
        var current = 0
        var longest = 0
        var todayDone = false
        /// Last 7 days, oldest first; last element is today.
        var lastSevenDays: [Day] = []

        var atRisk: Bool { current > 0 && !todayDone }

        init() {}

        enum CodingKeys: String, CodingKey {
            case current, longest, todayDone, lastSevenDays
        }
    }

    struct Day: Codable, Hashable, Sendable {
        var date: Date
        var done: Bool

        enum CodingKeys: String, CodingKey {
            case date, done
        }
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

        enum CodingKeys: String, CodingKey {
            case totalSeconds, completedEpisodes, seriesCount, topSeriesTitle, weekdaySeconds
        }
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

        enum CodingKeys: String, CodingKey {
            case slug, title, episodeLabel, progress, remainingSeconds, updatedAt, coverFileName, isNextEpisode
        }
    }
}

// Tolerant decoding lives in extensions so the memberwise initializers stay available.

extension WidgetSnapshot {
    init(from decoder: Decoder) throws {
        self.init()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = try c.decodeIfPresent(Int.self, forKey: .version) ?? WidgetSnapshot.currentVersion
        generatedAt = try c.decodeIfPresent(Date.self, forKey: .generatedAt) ?? Date()
        streak = try c.decodeIfPresent(Streak.self, forKey: .streak) ?? Streak()
        week = try c.decodeIfPresent(Period.self, forKey: .week) ?? Period()
        month = try c.decodeIfPresent(Period.self, forKey: .month) ?? Period()
        continueWatching = try c.decodeIfPresent([ContinueItem].self, forKey: .continueWatching) ?? []
    }
}

extension WidgetSnapshot.Streak {
    init(from decoder: Decoder) throws {
        self.init()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        current = try c.decodeIfPresent(Int.self, forKey: .current) ?? 0
        longest = try c.decodeIfPresent(Int.self, forKey: .longest) ?? 0
        todayDone = try c.decodeIfPresent(Bool.self, forKey: .todayDone) ?? false
        lastSevenDays = try c.decodeIfPresent([WidgetSnapshot.Day].self, forKey: .lastSevenDays) ?? []
    }
}

extension WidgetSnapshot.Day {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let date = try c.decode(Date.self, forKey: .date)
        let done = try c.decodeIfPresent(Bool.self, forKey: .done) ?? false
        self.init(date: date, done: done)
    }
}

extension WidgetSnapshot.Period {
    init(from decoder: Decoder) throws {
        self.init()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        totalSeconds = try c.decodeIfPresent(Double.self, forKey: .totalSeconds) ?? 0
        completedEpisodes = try c.decodeIfPresent(Int.self, forKey: .completedEpisodes) ?? 0
        seriesCount = try c.decodeIfPresent(Int.self, forKey: .seriesCount) ?? 0
        topSeriesTitle = try c.decodeIfPresent(String.self, forKey: .topSeriesTitle)
        weekdaySeconds = try c.decodeIfPresent([Double].self, forKey: .weekdaySeconds) ?? Array(repeating: 0, count: 7)
    }
}

extension WidgetSnapshot.ContinueItem {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let slug = try c.decode(String.self, forKey: .slug)
        let title = try c.decode(String.self, forKey: .title)
        self.init(
            slug: slug,
            title: title,
            episodeLabel: try c.decodeIfPresent(String.self, forKey: .episodeLabel) ?? "",
            progress: try c.decodeIfPresent(Double.self, forKey: .progress) ?? 0,
            remainingSeconds: try c.decodeIfPresent(Double.self, forKey: .remainingSeconds) ?? 0,
            updatedAt: try c.decodeIfPresent(Date.self, forKey: .updatedAt) ?? Date(),
            coverFileName: try c.decodeIfPresent(String.self, forKey: .coverFileName),
            isNextEpisode: try c.decodeIfPresent(Bool.self, forKey: .isNextEpisode) ?? false)
    }
}

/// Shared constants and file locations used by app and widget.
enum WidgetShared {
    /// Base App Group id as declared in the entitlements.
    static let baseAppGroupID = "group.com.aniworldios.app"

    /// App Group id actually usable at runtime. AltStore/SideStore rewrite the group to e.g.
    /// `group.com.aniworldios.app.<TEAMID>` and list the real ids in the Info.plist key
    /// `ALTAppGroups` (of the app, not necessarily of the extension). Resolved once and cached.
    static var appGroupID: String { resolvedGroup.id }

    /// Candidates in priority order (resolved id first, then the constant).
    private static let candidateIDs: [String] = {
        var ids: [String] = []
        func add(_ list: [String]) {
            for id in list where id.hasPrefix(baseAppGroupID) && !ids.contains(id) { ids.append(id) }
        }
        add(altAppGroups(in: Bundle.main.infoDictionary))
        add(altAppGroups(in: containingAppInfo()))
        add([baseAppGroupID])
        return ids
    }()

    /// First candidate with a reachable container, else the first candidate.
    private static let resolvedGroup: (id: String, url: URL?) = {
        for id in candidateIDs {
            if let url = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: id) {
                return (id, url)
            }
        }
        return (candidateIDs.first ?? baseAppGroupID, nil)
    }()

    private static func altAppGroups(in info: [String: Any]?) -> [String] {
        (info?["ALTAppGroups"] as? [String]) ?? []
    }

    /// Info.plist of the containing app when running inside an `.appex` (`<App>.app/PlugIns/<X>.appex`).
    private static func containingAppInfo() -> [String: Any]? {
        let bundleURL = Bundle.main.bundleURL
        guard bundleURL.pathExtension == "appex" else { return nil }
        let appURL = bundleURL.deletingLastPathComponent().deletingLastPathComponent()
        guard appURL.pathExtension == "app" else { return nil }
        let plistURL = appURL.appendingPathComponent("Info.plist")
        guard let data = try? Data(contentsOf: plistURL),
              let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil)
        else { return nil }
        return plist as? [String: Any]
    }

    static let urlScheme = "aniworld"

    /// Widget kinds (WidgetConfiguration `kind`), used for targeted reloads.
    enum Kind {
        static let streak = "StreakWidget"
        static let continueWatching = "ContinueWatchingWidget"
        static let stats = "StatsWidget"
    }

    /// `nil` when the App Group is not available (e.g. sideloaded without the entitlement).
    static var containerURL: URL? {
        resolvedGroup.url
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
