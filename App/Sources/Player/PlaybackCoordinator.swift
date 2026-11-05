import Foundation
import Observation
import AniworldKit

/// One playback session presented full screen. Owned by Agent C.
struct PlaybackSession: Identifiable, Hashable {
    let id = UUID()
    var series: SeriesSummary
    var episode: EpisodeRef
    /// Episodes of the current season, for next/previous. May be empty — the
    /// player then loads them itself.
    var seasonEpisodes: [EpisodeRef]
    var language: StreamLanguage?
    /// Start position in seconds (nil = resume from saved progress / start).
    var startAt: Double?
}

/// Entry point the UI uses to start playback. RootView presents
/// `PlayerScreen(session:)` whenever `activeSession` is non-nil.
@MainActor
@Observable
final class PlaybackCoordinator {
    var activeSession: PlaybackSession?
    /// True while Picture in Picture is active: the full-screen player stays mounted (keeping the
    /// AVPlayer alive) but is hidden so the user can browse the app.
    var isMinimized = false

    @ObservationIgnored let service: AniworldService
    @ObservationIgnored let library: LibraryStore
    @ObservationIgnored let settings: SettingsStore
    @ObservationIgnored private var resumeTask: Task<Void, Never>?

    init(service: AniworldService, library: LibraryStore, settings: SettingsStore) {
        self.service = service
        self.library = library
        self.settings = settings
    }

    /// Plays `episode`. `language` nil → series' preferred language, then settings priority.
    func play(series: SeriesSummary, episode: EpisodeRef, seasonEpisodes: [EpisodeRef] = [],
              language: StreamLanguage? = nil, fromStart: Bool = false) {
        isMinimized = false
        activeSession = PlaybackSession(
            series: series, episode: episode, seasonEpisodes: seasonEpisodes,
            language: language ?? library.preferredLanguage(seriesSlug: series.slug),
            startAt: fromStart ? 0 : nil
        )
    }

    /// Resumes a "Weiterschauen" entry; if it was finished, plays the next episode.
    func resume(_ entry: WatchEntry) {
        resumeTask?.cancel()
        guard entry.isFinished else {
            play(series: entry.series, episode: entry.episode, language: entry.language)
            return
        }
        resumeTask = Task { [weak self] in
            guard let self else { return }
            let next = await self.nextEpisode(after: entry.episode, in: entry.series, seasonEpisodes: [])
            if Task.isCancelled { return }
            if case let (episode, episodes)? = next {
                self.play(series: entry.series, episode: episode, seasonEpisodes: episodes,
                          language: entry.language, fromStart: true)
            } else {
                self.play(series: entry.series, episode: entry.episode, language: entry.language,
                          fromStart: true)
            }
        }
    }

    /// Next episode after `after`: same season first, then the first episode of the next
    /// season (films and season 0 are skipped unless `after` is a film). Returns the episode
    /// together with the episode list of its season. nil if there is none or on network errors.
    func nextEpisode(after: EpisodeRef, in series: SeriesSummary,
                     seasonEpisodes: [EpisodeRef]) async -> (EpisodeRef, [EpisodeRef])? {
        var current = seasonEpisodes.filter { $0.season == after.season }
        if current.isEmpty || !current.contains(where: { $0.id == after.id }) {
            guard let fetched = try? await service.episodes(slug: series.slug, season: after.season) else {
                return nil
            }
            current = fetched
        }
        let sorted = current.sorted { $0.number < $1.number }
        if let next = sorted.first(where: { $0.number > after.number }) {
            return (next, sorted)
        }
        // Films have no "next season".
        if after.season == 0 { return nil }

        guard let detail = try? await service.seriesDetail(slug: series.slug) else { return nil }
        let later = detail.seasons.map(\.number).filter { $0 > after.season }.sorted()
        for number in later {
            if Task.isCancelled { return nil }
            guard let eps = try? await service.episodes(slug: series.slug, season: number) else { continue }
            let ordered = eps.sorted { $0.number < $1.number }
            if let first = ordered.first { return (first, ordered) }
        }
        return nil
    }

    func dismiss() {
        isMinimized = false
        activeSession = nil
    }
}
