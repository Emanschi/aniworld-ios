import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Live implementation of `AniworldService` against aniworld.to.
public final class AniworldClient: AniworldService, @unchecked Sendable {
    public static let defaultBaseURL = URL(string: "https://aniworld.to")!
    public static let userAgent =
        "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1"

    public let baseURL: URL

    private let http: HTTPClient
    private let resolver: StreamResolver

    public convenience init(baseURL: URL = AniworldClient.defaultBaseURL) {
        self.init(baseURL: baseURL, http: HTTPClient(), extractors: .default)
    }

    init(baseURL: URL, http: HTTPClient, extractors: ExtractorRegistry,
         skipTransport: HTTPFetching = URLSessionTransport()) {
        self.baseURL = baseURL
        self.http = http
        self.resolver = StreamResolver(http: http, extractors: extractors)
        self.onlineSkip = OnlineSkipClient(transport: skipTransport)
    }

    private let onlineSkip: OnlineSkipClient

    public func onlineSkipTimes(seriesTitle: String, seriesSlug: String, season: Int, episode: Int) async -> [SkipTime] {
        await onlineSkip.skipTimes(seriesTitle: seriesTitle, seriesSlug: seriesSlug, season: season, episode: episode)
    }

    private func url(_ path: String) -> URL { Support.absoluteURL(path, base: baseURL)! }

    public func search(_ query: String) async throws -> [SeriesSummary] {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return [] }
        var request = URLRequest(url: url("/ajax/search"))
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded; charset=UTF-8", forHTTPHeaderField: "Content-Type")
        request.setValue("XMLHttpRequest", forHTTPHeaderField: "X-Requested-With")
        request.setValue(baseURL.absoluteString, forHTTPHeaderField: "Origin")
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        let encoded = query.addingPercentEncoding(withAllowedCharacters: allowed) ?? query
        request.httpBody = Data("keyword=\(encoded)".utf8)
        let response = try await http.send(request)
        guard response.status < 400 else { throw AniworldError.http(status: response.status, url: response.url) }
        return SearchParser.parse(response.data, query: query, baseURL: baseURL)
    }

    public func seriesDetail(slug: String) async throws -> SeriesDetail {
        let html = try await http.getText(url("/anime/stream/\(slug)"))
        return try SeriesParser.parseDetail(html, slug: slug, baseURL: baseURL)
    }

    public func episodes(slug: String, season: Int) async throws -> [EpisodeRef] {
        let html = try await http.getText(url(SeriesParser.seasonPath(slug: slug, season: season)))
        return SeriesParser.parseEpisodes(html, slug: slug, season: season, baseURL: baseURL)
    }

    public func hosters(for episode: EpisodeRef) async throws -> [HosterLink] {
        let html = try await http.getText(episode.url)
        return EpisodeParser.parseHosters(html, baseURL: baseURL)
    }

    public func availableLanguages(_ hosters: [HosterLink], preferences: StreamPreferences) -> [StreamLanguage] {
        StreamResolver.availableLanguages(hosters, preferences: preferences)
    }

    public func resolveStream(hosters: [HosterLink], language: StreamLanguage?, preferences: StreamPreferences,
                              verify: Bool, excluding: Set<String>) async throws -> ResolvedStream {
        try await resolver.resolve(hosters: hosters, language: language, preferences: preferences,
                                   verify: verify, excluding: excluding)
    }

    public func homeSections() async throws -> [HomeSection] {
        HomeParser.parse(try await http.getText(baseURL), baseURL: baseURL)
    }

    public func genres() async throws -> [GenreRef] {
        GenreParser.parseGenres(try await http.getText(baseURL))
    }

    /// All series of a genre, paging through `/genre/<slug>/<n>`. Cached per genre for 30 minutes, so
    /// combining genres in the search filter only loads each genre once.
    /// (`/animes` is not usable here: it lists every series only under its main genre.)
    public func series(inGenre slug: String) async throws -> [SeriesSummary] {
        let slug = slug.trimmingCharacters(in: CharacterSet(charactersIn: "/ \n\t")).lowercased()
        guard !slug.isEmpty, !slug.contains("/") else { return [] }
        return try await genreCache.value(for: slug) { try await self.pagedGenre(slug: slug) }
    }

    private let genreCache = KeyedCache<[SeriesSummary]>(lifetime: 30 * 60)

    private func pagedGenre(slug: String) async throws -> [SeriesSummary] {
        let firstHTML = try await http.getText(url("/genre/\(slug)"))
        let maxPages = 50
        var seen = Set<String>()
        var out: [SeriesSummary] = []
        for s in GenreParser.parseGenrePage(firstHTML, baseURL: baseURL) where seen.insert(s.slug).inserted {
            out.append(s)
        }
        let last = min(GenreParser.lastPage(firstHTML, slug: slug), maxPages)
        guard last >= 2 else { return out }
        for page in 2...last {
            try Task.checkCancellation()
            let html = try await http.getText(url("/genre/\(slug)/\(page)"))
            var added = 0
            for s in GenreParser.parseGenrePage(html, baseURL: baseURL) where seen.insert(s.slug).inserted {
                out.append(s)
                added += 1
            }
            if added == 0 { break }
        }
        return out
    }

    public func allSeries() async throws -> [SeriesSummary] {
        let list = GenreParser.parseSeriesList(try await http.getText(url("/animes-alphabet")), baseURL: baseURL)
        return list.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    public func releaseCalendar() async throws -> [CalendarDay] {
        CalendarParser.parse(try await http.getText(url("/animekalender")), baseURL: baseURL)
    }

    /// Skip times come from the bundled offline database only (no network lookup).
    public func skipTimes(seriesTitle: String, seriesSlug: String, season: Int, episode: Int) async -> [SkipTime] {
        LocalSkipDatabase.shared.findSkipTimes(
            seriesSlug: seriesSlug,
            seriesTitle: seriesTitle,
            season: season,
            episode: episode
        ) ?? []
    }
}

/// Caches expensive values per key for a while; concurrent callers for the same key share one load.
actor KeyedCache<Value: Sendable> {
    private let lifetime: TimeInterval
    private var stored: [String: (value: Value, date: Date)] = [:]
    private var loading: [String: Task<Value, Error>] = [:]

    init(lifetime: TimeInterval) { self.lifetime = lifetime }

    func value(for key: String, _ load: @escaping @Sendable () async throws -> Value) async throws -> Value {
        if let hit = stored[key], Date().timeIntervalSince(hit.date) < lifetime { return hit.value }
        if let running = loading[key] { return try await running.value }
        let task = Task { try await load() }
        loading[key] = task
        defer { loading[key] = nil }
        let value = try await task.value
        stored[key] = (value, Date())
        return value
    }
}
