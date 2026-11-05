import Foundation

/// One continuous stretch of watching a single episode (the raw data behind the statistics).
public struct WatchSession: Codable, Hashable, Identifiable, Sendable {
    public var id: String
    public var seriesSlug: String
    public var seriesTitle: String
    public var coverURL: URL?
    /// 0 = films.
    public var season: Int
    public var episode: Int
    public var language: StreamLanguage?
    public var hoster: String
    public var startedAt: Date
    public var endedAt: Date
    /// Real time the video was actually playing (not the media distance at higher speeds).
    public var watchedSeconds: Double
    /// Average playback speed while playing (1.0 = normal).
    public var playbackRate: Double
    public var episodeDuration: Double
    /// The episode reached at least 90 % (or played to its end).
    public var completed: Bool
    /// Media seconds skipped through intro / outro / recap skips.
    public var skippedSeconds: Double
    /// Played from a download.
    public var wasOffline: Bool
    public var deviceID: String

    public init(id: String = UUID().uuidString, seriesSlug: String, seriesTitle: String, coverURL: URL? = nil,
                season: Int, episode: Int, language: StreamLanguage? = nil, hoster: String = "",
                startedAt: Date, endedAt: Date, watchedSeconds: Double, playbackRate: Double = 1,
                episodeDuration: Double = 0, completed: Bool = false, skippedSeconds: Double = 0,
                wasOffline: Bool = false, deviceID: String = "") {
        self.id = id
        self.seriesSlug = seriesSlug
        self.seriesTitle = seriesTitle
        self.coverURL = coverURL
        self.season = season
        self.episode = episode
        self.language = language
        self.hoster = hoster
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.watchedSeconds = watchedSeconds
        self.playbackRate = playbackRate
        self.episodeDuration = episodeDuration
        self.completed = completed
        self.skippedSeconds = skippedSeconds
        self.wasOffline = wasOffline
        self.deviceID = deviceID
    }

    /// Identifies the episode independent of the session ("slug-s1e3").
    public var episodeKey: String { "\(seriesSlug)-s\(season)e\(episode)" }

    private enum CodingKeys: String, CodingKey {
        case id, season, hoster
        case seriesSlug = "slug", seriesTitle = "title", coverURL = "cover", episode = "ep"
        case language = "lang", startedAt = "start", endedAt = "end", watchedSeconds = "watched"
        case playbackRate = "rate", episodeDuration = "dur", completed = "done", skippedSeconds = "skipped"
        case wasOffline = "offline", deviceID = "device"
    }

    /// Tolerant decoding: only the identifying fields are required.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        seriesSlug = try c.decode(String.self, forKey: .seriesSlug)
        seriesTitle = try c.decodeIfPresent(String.self, forKey: .seriesTitle) ?? seriesSlug
        coverURL = try c.decodeIfPresent(URL.self, forKey: .coverURL)
        season = try c.decodeIfPresent(Int.self, forKey: .season) ?? 1
        episode = try c.decodeIfPresent(Int.self, forKey: .episode) ?? 1
        language = try c.decodeIfPresent(StreamLanguage.self, forKey: .language)
        hoster = try c.decodeIfPresent(String.self, forKey: .hoster) ?? ""
        startedAt = try c.decode(Date.self, forKey: .startedAt)
        endedAt = try c.decodeIfPresent(Date.self, forKey: .endedAt) ?? startedAt
        watchedSeconds = try c.decodeIfPresent(Double.self, forKey: .watchedSeconds) ?? 0
        playbackRate = try c.decodeIfPresent(Double.self, forKey: .playbackRate) ?? 1
        episodeDuration = try c.decodeIfPresent(Double.self, forKey: .episodeDuration) ?? 0
        completed = try c.decodeIfPresent(Bool.self, forKey: .completed) ?? false
        skippedSeconds = try c.decodeIfPresent(Double.self, forKey: .skippedSeconds) ?? 0
        wasOffline = try c.decodeIfPresent(Bool.self, forKey: .wasOffline) ?? false
        deviceID = try c.decodeIfPresent(String.self, forKey: .deviceID) ?? ""
    }
}

/// Genres and age rating of a series, remembered so statistics can show favourite genres.
public struct SeriesMeta: Codable, Hashable, Sendable {
    public var genres: [String]
    public var ageRating: Int?
    public var updatedAt: Date

    public init(genres: [String], ageRating: Int?, updatedAt: Date) {
        self.genres = genres
        self.ageRating = ageRating
        self.updatedAt = updatedAt
    }
}

/// The syncable part of the statistics.
public struct StatsState: Codable, Hashable, Sendable {
    public var sessions: [WatchSession]
    /// slug → genres / age rating.
    public var seriesMeta: [String: SeriesMeta]
    /// Time of the last "Statistik zurücksetzen"; sessions that ended at or before it are dropped.
    public var resetAt: Date?

    public init(sessions: [WatchSession] = [], seriesMeta: [String: SeriesMeta] = [:], resetAt: Date? = nil) {
        self.sessions = sessions
        self.seriesMeta = seriesMeta
        self.resetAt = resetAt
    }
}

/// Pure merge of statistics from several devices.
///
/// - sessions: union by `id`; on the same id the newer `endedAt` wins (then more watched time, then
///   a deterministic tie-break), so the result does not depend on the order of the inputs;
/// - `resetAt`: the newest reset wins and every session that ended at or before it is dropped;
/// - sessions older than `retention` are dropped;
/// - series meta: per slug the newer `updatedAt` wins.
public enum StatsMerge {
    public static let retention: TimeInterval = 730 * 24 * 3600

    public static func merge(_ states: [StatsState], now: Date = Date()) -> StatsState {
        let reset: Date? = states.compactMap { $0.resetAt }.max()
        let floor: Date = max(reset ?? Date.distantPast, now.addingTimeInterval(-retention))

        var best: [String: WatchSession] = [:]
        for state in states {
            for session in state.sessions where session.endedAt > floor {
                if let current = best[session.id] {
                    if isBetter(session, than: current) { best[session.id] = session }
                } else {
                    best[session.id] = session
                }
            }
        }
        let sessions: [WatchSession] = best.values.sorted { (a: WatchSession, b: WatchSession) -> Bool in
            a.startedAt != b.startedAt ? a.startedAt < b.startedAt : a.id < b.id
        }

        var meta: [String: SeriesMeta] = [:]
        for state in states {
            for (slug, value) in state.seriesMeta {
                if let current = meta[slug] {
                    let newer = value.updatedAt > current.updatedAt
                    let tie = value.updatedAt == current.updatedAt
                        && value.genres.joined(separator: ",") > current.genres.joined(separator: ",")
                    if newer || tie { meta[slug] = value }
                } else {
                    meta[slug] = value
                }
            }
        }
        return StatsState(sessions: sessions, seriesMeta: meta, resetAt: reset)
    }

    private static func isBetter(_ a: WatchSession, than b: WatchSession) -> Bool {
        if a.endedAt != b.endedAt { return a.endedAt > b.endedAt }
        if a.watchedSeconds != b.watchedSeconds { return a.watchedSeconds > b.watchedSeconds }
        if a.skippedSeconds != b.skippedSeconds { return a.skippedSeconds > b.skippedSeconds }
        if a.completed != b.completed { return a.completed }
        return a.deviceID > b.deviceID
    }
}
