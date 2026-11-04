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

    @ObservationIgnored let service: AniworldService
    @ObservationIgnored let library: LibraryStore
    @ObservationIgnored let settings: SettingsStore

    init(service: AniworldService, library: LibraryStore, settings: SettingsStore) {
        self.service = service
        self.library = library
        self.settings = settings
    }

    /// Plays `episode`. `language` nil → series' preferred language, then settings priority.
    func play(series: SeriesSummary, episode: EpisodeRef, seasonEpisodes: [EpisodeRef] = [],
              language: StreamLanguage? = nil, fromStart: Bool = false) {
        activeSession = PlaybackSession(
            series: series, episode: episode, seasonEpisodes: seasonEpisodes,
            language: language ?? library.preferredLanguage(seriesSlug: series.slug),
            startAt: fromStart ? 0 : nil
        )
    }

    /// Resumes a "Weiterschauen" entry; if it was finished, plays the next episode.
    func resume(_ entry: WatchEntry) {
        // TODO(Agent C): finished → find next episode (incl. next season) via service
        play(series: entry.series, episode: entry.episode, language: entry.language)
    }

    func dismiss() {
        activeSession = nil
    }
}
