import Foundation
import AniworldKit

/// A preferred stream language with the time it was chosen (for last-writer-wins).
struct LanguageChoice: Codable, Hashable, Sendable {
    var language: StreamLanguage
    var updatedAt: Date
}

/// The syncable part of the library as a plain value (no device information).
struct LibraryState: Codable, Equatable, Sendable {
    var favorites: [FavoriteEntry] = []
    /// slug → time the favorite was removed.
    var favoriteTombstones: [String: Date] = [:]
    var history: [WatchEntry] = []
    /// slug → time the history entry was removed.
    var historyTombstones: [String: Date] = [:]
    /// Time the whole history was cleared.
    var historyClearedAt: Date?
    /// Progress per `EpisodeRef.id`.
    var progress: [String: EpisodeProgress] = [:]
    /// Preferred language per series slug.
    var languages: [String: LanguageChoice] = [:]
    /// Time of the last "reset everything".
    var resetAt: Date?
    /// User-defined intro/outro times (key = `CustomSkip.key`).
    var customSkips: [CustomSkip] = []
    /// key → time the custom entry was removed.
    var customSkipTombstones: [String: Date] = [:]
}

/// What one device writes to `.aniworld-sync/devices/<deviceID>.json`.
struct SyncSnapshot: Codable, Sendable {
    /// Stays 1: the statistics fields below are optional additions. Older app versions simply ignore
    /// them (and omit them when writing their own file), newer ones fall back to empty values.
    static let currentSchemaVersion = 1

    var schemaVersion: Int
    var deviceID: String
    var deviceName: String
    var writtenAt: Date
    var favorites: [FavoriteEntry]
    var favoriteTombstones: [String: Date]
    var history: [WatchEntry]
    var historyTombstones: [String: Date]
    var historyClearedAt: Date?
    var progress: [String: EpisodeProgress]
    var languages: [String: LanguageChoice]
    var resetAt: Date?
    var customSkips: [CustomSkip]
    var customSkipTombstones: [String: Date]
    /// Watch sessions recorded on *this* device only (each device writes its own; merge = union).
    var statsSessions: [WatchSession]
    var statsSeriesMeta: [String: SeriesMeta]
    var statsResetAt: Date?

    init(deviceID: String, deviceName: String, writtenAt: Date = Date(), state: LibraryState,
         stats: StatsState = StatsState()) {
        schemaVersion = Self.currentSchemaVersion
        self.deviceID = deviceID
        self.deviceName = deviceName
        self.writtenAt = writtenAt
        favorites = state.favorites
        favoriteTombstones = state.favoriteTombstones
        history = state.history
        historyTombstones = state.historyTombstones
        historyClearedAt = state.historyClearedAt
        progress = state.progress
        languages = state.languages
        resetAt = state.resetAt
        customSkips = state.customSkips
        customSkipTombstones = state.customSkipTombstones
        statsSessions = stats.sessions
        statsSeriesMeta = stats.seriesMeta
        statsResetAt = stats.resetAt
    }

    var statsState: StatsState {
        StatsState(sessions: statsSessions, seriesMeta: statsSeriesMeta, resetAt: statsResetAt)
    }

    var state: LibraryState {
        LibraryState(favorites: favorites, favoriteTombstones: favoriteTombstones,
                     history: history, historyTombstones: historyTombstones,
                     historyClearedAt: historyClearedAt, progress: progress,
                     languages: languages, resetAt: resetAt,
                     customSkips: customSkips, customSkipTombstones: customSkipTombstones)
    }

    enum CodingKeys: String, CodingKey {
        case schemaVersion, deviceID, deviceName, writtenAt, favorites, favoriteTombstones
        case history, historyTombstones, historyClearedAt, progress, languages, resetAt
        case customSkips, customSkipTombstones
        case statsSessions, statsSeriesMeta, statsResetAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try c.decode(Int.self, forKey: .schemaVersion)
        deviceID = try c.decode(String.self, forKey: .deviceID)
        deviceName = try c.decodeIfPresent(String.self, forKey: .deviceName) ?? ""
        writtenAt = try c.decodeIfPresent(Date.self, forKey: .writtenAt) ?? .distantPast
        favorites = try c.decodeIfPresent([FavoriteEntry].self, forKey: .favorites) ?? []
        favoriteTombstones = try c.decodeIfPresent([String: Date].self, forKey: .favoriteTombstones) ?? [:]
        history = try c.decodeIfPresent([WatchEntry].self, forKey: .history) ?? []
        historyTombstones = try c.decodeIfPresent([String: Date].self, forKey: .historyTombstones) ?? [:]
        historyClearedAt = try c.decodeIfPresent(Date.self, forKey: .historyClearedAt)
        progress = try c.decodeIfPresent([String: EpisodeProgress].self, forKey: .progress) ?? [:]
        languages = try c.decodeIfPresent([String: LanguageChoice].self, forKey: .languages) ?? [:]
        resetAt = try c.decodeIfPresent(Date.self, forKey: .resetAt)
        customSkips = try c.decodeIfPresent([CustomSkip].self, forKey: .customSkips) ?? []
        customSkipTombstones = try c.decodeIfPresent([String: Date].self, forKey: .customSkipTombstones) ?? [:]
        statsSessions = try c.decodeIfPresent([WatchSession].self, forKey: .statsSessions) ?? []
        statsSeriesMeta = try c.decodeIfPresent([String: SeriesMeta].self, forKey: .statsSeriesMeta) ?? [:]
        statsResetAt = try c.decodeIfPresent(Date.self, forKey: .statsResetAt)
    }
}
