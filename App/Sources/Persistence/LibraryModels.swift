import Foundation
import AniworldKit

/// Saved progress of a single episode.
struct EpisodeProgress: Codable, Hashable, Sendable {
    var position: Double      // seconds
    var duration: Double      // seconds, 0 if unknown
    var watched: Bool         // true once >= 90 % or marked manually
    var updatedAt: Date

    var fraction: Double { duration > 0 ? min(max(position / duration, 0), 1) : 0 }
}

/// One row of "Weiterschauen": the most recent episode of a series.
/// There is at most one entry per series; newest first.
struct WatchEntry: Codable, Hashable, Identifiable, Sendable {
    var series: SeriesSummary
    var episode: EpisodeRef
    var language: StreamLanguage?
    var position: Double
    var duration: Double
    var updatedAt: Date
    /// The episode was finished — tapping the entry should play the next episode.
    var isFinished: Bool

    var id: String { series.slug }
    var fraction: Double { duration > 0 ? min(max(position / duration, 0), 1) : 0 }
    var remaining: Double { max(duration - position, 0) }
}

/// A series the user saved, with the time it was added.
struct FavoriteEntry: Codable, Hashable, Identifiable, Sendable {
    var series: SeriesSummary
    var addedAt: Date
    var id: String { series.slug }
}

/// User-defined intro/outro times for one episode or a whole season of a series.
/// Takes precedence over the bundled skip database.
struct CustomSkip: Codable, Hashable, Identifiable, Sendable {
    var seriesSlug: String
    var season: Int
    /// nil = applies to the whole season.
    var episode: Int?
    var introStart: Double?
    var introEnd: Double?
    var outroStart: Double?
    var outroEnd: Double?
    var updatedAt: Date

    var id: String { key }
    var key: String { Self.key(seriesSlug: seriesSlug, season: season, episode: episode) }

    static func key(seriesSlug: String, season: Int, episode: Int?) -> String {
        "\(seriesSlug)|s\(season)|e\(episode.map { String($0) } ?? "all")"
    }

    var hasIntro: Bool {
        guard let s = introStart, let e = introEnd else { return false }
        return e > s
    }

    var hasOutro: Bool {
        guard let s = outroStart, let e = outroEnd else { return false }
        return e > s
    }
}
