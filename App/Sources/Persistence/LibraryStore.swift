import Foundation
import Observation
import AniworldKit

/// Local library: favorites, continue-watching history and per-episode progress.
/// Persisted as JSON in Application Support. Owned by Agent C; the public API
/// below is the contract the UI codes against — extend it, don't break it.
@MainActor
@Observable
final class LibraryStore {
    /// Saved series, newest first.
    private(set) var favorites: [FavoriteEntry] = []
    /// "Weiterschauen", newest first, one entry per series.
    private(set) var history: [WatchEntry] = []

    init() {
        // TODO(Agent C): load from disk
    }

    // MARK: Favorites

    func isFavorite(_ slug: String) -> Bool {
        favorites.contains { $0.series.slug == slug }
    }

    func toggleFavorite(_ series: SeriesSummary) {
        // TODO(Agent C)
    }

    func removeFavorite(_ slug: String) {
        // TODO(Agent C)
    }

    // MARK: Progress & history

    func progress(for episode: EpisodeRef) -> EpisodeProgress? {
        nil // TODO(Agent C)
    }

    /// Called periodically by the player and when playback stops.
    func updateProgress(series: SeriesSummary, episode: EpisodeRef, language: StreamLanguage?,
                        position: Double, duration: Double) {
        // TODO(Agent C)
    }

    func setWatched(_ watched: Bool, episode: EpisodeRef, series: SeriesSummary) {
        // TODO(Agent C)
    }

    /// Marks all episodes up to and including `episode` in its season as watched.
    func markWatchedUpTo(_ episode: EpisodeRef, in episodes: [EpisodeRef], series: SeriesSummary) {
        // TODO(Agent C)
    }

    func removeFromHistory(_ slug: String) {
        // TODO(Agent C)
    }

    func clearHistory() {
        // TODO(Agent C)
    }

    /// Most recent history entry for a series (for "Fortsetzen" on the detail page).
    func lastWatched(seriesSlug: String) -> WatchEntry? {
        history.first { $0.series.slug == seriesSlug }
    }

    /// Language last used for a series, to preselect it next time.
    func preferredLanguage(seriesSlug: String) -> StreamLanguage? {
        nil // TODO(Agent C)
    }

    func setPreferredLanguage(_ language: StreamLanguage, seriesSlug: String) {
        // TODO(Agent C)
    }

    /// Wipes favorites, history and progress.
    func resetAll() {
        // TODO(Agent C)
    }
}
