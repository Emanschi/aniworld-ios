import Foundation

/// Everything the app needs from aniworld.to. `AniworldClient` is the live
/// implementation; the app also ships a mock for previews.
public protocol AniworldService: Sendable {
    /// `POST /ajax/search` — series roots only, de-duplicated, title matches first.
    func search(_ query: String) async throws -> [SeriesSummary]

    /// Series landing page: description, cover, genres, years, seasons (0 = films).
    func seriesDetail(slug: String) async throws -> SeriesDetail

    /// Episodes of one season (or films for season 0), ordered by number.
    func episodes(slug: String, season: Int) async throws -> [EpisodeRef]

    /// Hoster entries of an episode page with their resolved languages.
    func hosters(for episode: EpisodeRef) async throws -> [HosterLink]

    /// Languages offered by `hosters`, ordered by `preferences.languagePriority`.
    func availableLanguages(_ hosters: [HosterLink], preferences: StreamPreferences) -> [StreamLanguage]

    /// Tries hosters (language priority, then hoster priority; restricted to
    /// `language` when given) until one extracts and — if `verify` — passes the
    /// segment liveness check. Throws `AniworldError.noPlayableStream` otherwise.
    /// `excluding` skips hoster names already tried (used for in-player fallback).
    func resolveStream(
        hosters: [HosterLink],
        language: StreamLanguage?,
        preferences: StreamPreferences,
        verify: Bool,
        excluding: Set<String>
    ) async throws -> ResolvedStream

    /// Rows for the home screen parsed from the site's start page. May be empty.
    func homeSections() async throws -> [HomeSection]

    /// Liefert Intro-, Outro- und Recap-Zeitmarken für eine Episode (oder leer, falls keine vorliegen).
    func skipTimes(seriesTitle: String, seriesSlug: String, season: Int, episode: Int) async -> [SkipTime]

    /// Online-Zeitmarken von AniSkip (über AniList → MyAnimeList-ID). Leer bei keinem Treffer oder offline.
    /// Die App ruft das nur auf, wenn der Nutzer Online-Skip-Zeiten eingeschaltet hat.
    func onlineSkipTimes(seriesTitle: String, seriesSlug: String, season: Int, episode: Int) async -> [SkipTime]

    /// Genres offered by the site (language pseudo-genres excluded). May be empty.
    func genres() async throws -> [GenreRef]

    /// All series of a genre (`GenreRef.slug`); follows the site's pagination.
    func series(inGenre slug: String) async throws -> [SeriesSummary]

    /// The complete A–Z series list.
    func allSeries() async throws -> [SeriesSummary]

    /// Upcoming releases grouped by day (anime calendar).
    func releaseCalendar() async throws -> [CalendarDay]
}

public extension AniworldService {
    func genres() async throws -> [GenreRef] { [] }
    func series(inGenre slug: String) async throws -> [SeriesSummary] { [] }
    func allSeries() async throws -> [SeriesSummary] { [] }
    func releaseCalendar() async throws -> [CalendarDay] { [] }
}

public extension AniworldService {
    func skipTimes(seriesTitle: String, seriesSlug: String, season: Int, episode: Int) async -> [SkipTime] {
        []
    }

    func onlineSkipTimes(seriesTitle: String, seriesSlug: String, season: Int, episode: Int) async -> [SkipTime] {
        []
    }
}

public extension AniworldService {
    func resolveStream(
        hosters: [HosterLink],
        language: StreamLanguage? = nil,
        preferences: StreamPreferences = .default,
        verify: Bool = true
    ) async throws -> ResolvedStream {
        try await resolveStream(hosters: hosters, language: language, preferences: preferences,
                                verify: verify, excluding: [])
    }
}
