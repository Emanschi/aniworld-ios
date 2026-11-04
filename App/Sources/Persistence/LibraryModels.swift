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
