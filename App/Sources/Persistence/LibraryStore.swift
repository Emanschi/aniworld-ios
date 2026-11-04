import Foundation
import Observation
import UIKit
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
    /// Progress per `EpisodeRef.id`.
    private(set) var progressByEpisode: [String: EpisodeProgress] = [:]
    /// Preferred language per series slug.
    private(set) var languageBySlug: [String: StreamLanguage] = [:]

    @ObservationIgnored private let fileURL: URL?
    @ObservationIgnored private var saveTask: Task<Void, Never>?
    @ObservationIgnored private var lifecycleTokens: [NSObjectProtocol] = []

    private static let historyLimit = 50

    private struct Snapshot: Codable {
        var favorites: [FavoriteEntry] = []
        var history: [WatchEntry] = []
        var progress: [String: EpisodeProgress] = [:]
        var languages: [String: StreamLanguage] = [:]

        init() {}

        enum CodingKeys: String, CodingKey { case favorites, history, progress, languages }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            favorites = try c.decodeIfPresent([FavoriteEntry].self, forKey: .favorites) ?? []
            history = try c.decodeIfPresent([WatchEntry].self, forKey: .history) ?? []
            progress = try c.decodeIfPresent([String: EpisodeProgress].self, forKey: .progress) ?? [:]
            languages = try c.decodeIfPresent([String: StreamLanguage].self, forKey: .languages) ?? [:]
        }
    }

    /// - Parameter fileURL: override for tests/previews; default is Application Support/library.json.
    init(fileURL: URL? = LibraryStore.defaultFileURL()) {
        self.fileURL = fileURL
        load()
        let center = NotificationCenter.default
        let names: [Notification.Name] = [
            UIApplication.willResignActiveNotification,
            UIApplication.didEnterBackgroundNotification,
            UIApplication.willTerminateNotification,
        ]
        for name in names {
            let token = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.flush() }
            }
            lifecycleTokens.append(token)
        }
    }

    // MARK: Persistence

    nonisolated static func defaultFileURL() -> URL? {
        guard let base = try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                                      appropriateFor: nil, create: true) else { return nil }
        return base.appendingPathComponent("library.json")
    }

    private func load() {
        guard let fileURL, let data = try? Data(contentsOf: fileURL),
              let snap = try? JSONDecoder().decode(Snapshot.self, from: data) else { return }
        favorites = snap.favorites
        history = snap.history
        progressByEpisode = snap.progress
        languageBySlug = snap.languages
    }

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            guard !Task.isCancelled else { return }
            self?.flush()
        }
    }

    /// Writes the library to disk immediately (call when the app goes to the background).
    func flush() {
        saveTask?.cancel()
        saveTask = nil
        guard let fileURL else { return }
        var snap = Snapshot()
        snap.favorites = favorites
        snap.history = history
        snap.progress = progressByEpisode
        snap.languages = languageBySlug
        guard let data = try? JSONEncoder().encode(snap) else { return }
        try? data.write(to: fileURL, options: [.atomic])
    }

    // MARK: Favorites

    func isFavorite(_ slug: String) -> Bool {
        favorites.contains { $0.series.slug == slug }
    }

    func toggleFavorite(_ series: SeriesSummary) {
        if isFavorite(series.slug) {
            removeFavorite(series.slug)
        } else {
            favorites.insert(FavoriteEntry(series: series, addedAt: Date()), at: 0)
            scheduleSave()
        }
    }

    func removeFavorite(_ slug: String) {
        favorites.removeAll { $0.series.slug == slug }
        scheduleSave()
    }

    // MARK: Progress & history

    func progress(for episode: EpisodeRef) -> EpisodeProgress? {
        progressByEpisode[episode.id]
    }

    /// Called periodically by the player and when playback stops.
    func updateProgress(series: SeriesSummary, episode: EpisodeRef, language: StreamLanguage?,
                        position: Double, duration: Double) {
        guard position.isFinite, position >= 0 else { return }
        let duration = duration.isFinite && duration > 0 ? duration : 0
        let now = Date()
        let finished = duration > 0 && (position / duration >= 0.9 || duration - position < 60)

        var p = progressByEpisode[episode.id]
            ?? EpisodeProgress(position: 0, duration: 0, watched: false, updatedAt: now)
        p.position = position
        if duration > 0 { p.duration = duration }
        p.watched = p.watched || finished
        p.updatedAt = now
        progressByEpisode[episode.id] = p

        upsertHistory(WatchEntry(series: series, episode: episode, language: language,
                                 position: position, duration: p.duration,
                                 updatedAt: now, isFinished: finished))
        if let language { languageBySlug[series.slug] = language }
        scheduleSave()
    }

    func setWatched(_ watched: Bool, episode: EpisodeRef, series: SeriesSummary) {
        let now = Date()
        var p = progressByEpisode[episode.id]
            ?? EpisodeProgress(position: 0, duration: 0, watched: false, updatedAt: now)
        p.watched = watched
        p.updatedAt = now
        if watched {
            if p.duration > 0 { p.position = p.duration }
            progressByEpisode[episode.id] = p
            if !hasLaterHistoryEntry(than: episode) {
                upsertHistory(WatchEntry(series: series, episode: episode,
                                         language: languageBySlug[series.slug],
                                         position: p.position, duration: p.duration,
                                         updatedAt: now, isFinished: true))
            }
        } else {
            p.position = 0
            progressByEpisode[episode.id] = p
            if let entry = history.first(where: { $0.series.slug == series.slug }),
               entry.episode.id == episode.id {
                history.removeAll { $0.series.slug == series.slug }
            }
        }
        scheduleSave()
    }

    /// Marks all episodes up to and including `episode` in its season as watched.
    func markWatchedUpTo(_ episode: EpisodeRef, in episodes: [EpisodeRef], series: SeriesSummary) {
        let now = Date()
        var targets = episodes.filter { $0.season == episode.season && $0.number <= episode.number }
        if !targets.contains(where: { $0.id == episode.id }) { targets.append(episode) }
        for ep in targets {
            var p = progressByEpisode[ep.id]
                ?? EpisodeProgress(position: 0, duration: 0, watched: false, updatedAt: now)
            p.watched = true
            if p.duration > 0 { p.position = p.duration }
            p.updatedAt = now
            progressByEpisode[ep.id] = p
        }
        if !hasLaterHistoryEntry(than: episode) {
            let p = progressByEpisode[episode.id]
            upsertHistory(WatchEntry(series: series, episode: episode,
                                     language: languageBySlug[series.slug],
                                     position: p?.position ?? 0, duration: p?.duration ?? 0,
                                     updatedAt: now, isFinished: true))
        }
        scheduleSave()
    }

    func removeFromHistory(_ slug: String) {
        history.removeAll { $0.series.slug == slug }
        scheduleSave()
    }

    /// Clears the "Weiterschauen" list only; per-episode progress is kept.
    func clearHistory() {
        history.removeAll()
        scheduleSave()
    }

    /// Most recent history entry for a series (for "Fortsetzen" on the detail page).
    func lastWatched(seriesSlug: String) -> WatchEntry? {
        history.first { $0.series.slug == seriesSlug }
    }

    /// Language last used for a series, to preselect it next time.
    func preferredLanguage(seriesSlug: String) -> StreamLanguage? {
        languageBySlug[seriesSlug]
    }

    func setPreferredLanguage(_ language: StreamLanguage, seriesSlug: String) {
        languageBySlug[seriesSlug] = language
        scheduleSave()
    }

    /// Wipes favorites, history and progress.
    func resetAll() {
        favorites = []
        history = []
        progressByEpisode = [:]
        languageBySlug = [:]
        flush()
    }

    // MARK: Helpers

    private func upsertHistory(_ entry: WatchEntry) {
        history.removeAll { $0.series.slug == entry.series.slug }
        history.insert(entry, at: 0)
        if history.count > Self.historyLimit {
            history.removeLast(history.count - Self.historyLimit)
        }
    }

    /// True if the series' history entry already points at a later episode.
    private func hasLaterHistoryEntry(than episode: EpisodeRef) -> Bool {
        guard let entry = history.first(where: { $0.series.slug == episode.seriesSlug }) else { return false }
        let e = entry.episode
        if e.season == episode.season { return e.number > episode.number }
        if e.season == 0 || episode.season == 0 { return false }
        return e.season > episode.season
    }
}
