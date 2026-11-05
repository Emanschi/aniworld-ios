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
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
        // Skip times go to Application Support (not purged like Caches) so they stay for offline downloads.
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        self.init(baseURL: baseURL, http: HTTPClient(), extractors: .default,
                  genreCacheDirectory: caches?.appendingPathComponent("AniworldKit/genres", isDirectory: true),
                  skipCacheFile: support?.appendingPathComponent("AniworldKit/aniskip-cache.json"))
    }

    init(baseURL: URL, http: HTTPClient, extractors: ExtractorRegistry,
         skipTransport: HTTPFetching = URLSessionTransport(), genreCacheDirectory: URL? = nil,
         skipCacheFile: URL? = nil) {
        self.baseURL = baseURL
        self.http = http
        // Genre lists are many small pages; a shorter gap with a few requests in flight keeps a
        // large genre at a few seconds. 429/5xx still back off through HTTPClient.
        self.pagingHTTP = http.withThrottle(RequestThrottle(gap: .milliseconds(150)))
        self.resolver = StreamResolver(http: http, extractors: extractors)
        self.onlineSkip = OnlineSkipClient(transport: skipTransport, cacheFile: skipCacheFile)
        self.genreDiskCache = genreCacheDirectory
    }

    private let pagingHTTP: HTTPClient
    private let genreDiskCache: URL?

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

    /// All series of a genre, paging through `/genre/<slug>/<n>` (a few pages in flight).
    /// Cached in memory (30 min) and on disk (24 h), so combining genres or reopening the app is instant.
    /// (`/animes` is not usable here: it lists every series only under its main genre.)
    public func series(inGenre slug: String) async throws -> [SeriesSummary] {
        try await series(inGenre: slug, progress: { _ in })
    }

    public func series(inGenre slug: String,
                       progress: @escaping @Sendable ([SeriesSummary]) async -> Void) async throws -> [SeriesSummary] {
        let slug = slug.trimmingCharacters(in: CharacterSet(charactersIn: "/ \n\t")).lowercased()
        guard !slug.isEmpty, !slug.contains("/") else { return [] }
        let result = try await genreCache.value(for: slug) {
            if let cached = self.readGenreFromDisk(slug) { return cached }
            let list = try await self.pagedGenre(slug: slug, progress: progress)
            self.writeGenreToDisk(slug, list)
            return list
        }
        await progress(result)
        return result
    }

    private let genreCache = KeyedCache<[SeriesSummary]>(lifetime: 30 * 60)
    static let genreDiskLifetime: TimeInterval = 24 * 60 * 60
    static let genrePagesInFlight = 4

    private func pagedGenre(slug: String,
                            progress: @escaping @Sendable ([SeriesSummary]) async -> Void) async throws -> [SeriesSummary] {
        let firstHTML = try await pagingHTTP.getText(url("/genre/\(slug)"))
        var pages: [Int: [SeriesSummary]] = [1: GenreParser.parseGenrePage(firstHTML, baseURL: baseURL)]
        await progress(Self.merge(pages))
        let last = min(GenreParser.lastPage(firstHTML, slug: slug), 50)
        guard last >= 2 else { return Self.merge(pages) }

        try await withThrowingTaskGroup(of: (Int, [SeriesSummary]).self) { group in
            var next = 2
            while next <= last && next < 2 + Self.genrePagesInFlight {
                let page = next
                group.addTask { (page, try await self.genrePage(slug: slug, page: page)) }
                next += 1
            }
            while let done = try await group.next() {
                pages[done.0] = done.1
                await progress(Self.merge(pages))
                if next <= last {
                    let page = next
                    group.addTask { (page, try await self.genrePage(slug: slug, page: page)) }
                    next += 1
                }
            }
        }
        return Self.merge(pages)
    }

    private func genrePage(slug: String, page: Int) async throws -> [SeriesSummary] {
        let html = try await pagingHTTP.getText(url("/genre/\(slug)/\(page)"))
        return GenreParser.parseGenrePage(html, baseURL: baseURL)
    }

    /// Pages in site order, de-duplicated by slug.
    static func merge(_ pages: [Int: [SeriesSummary]]) -> [SeriesSummary] {
        var seen = Set<String>()
        var out: [SeriesSummary] = []
        for key in pages.keys.sorted() {
            for s in pages[key] ?? [] where seen.insert(s.slug).inserted { out.append(s) }
        }
        return out
    }

    private func genreFile(_ slug: String) -> URL? {
        genreDiskCache?.appendingPathComponent("\(slug).json")
    }

    private func readGenreFromDisk(_ slug: String) -> [SeriesSummary]? {
        guard let file = genreFile(slug),
              let attrs = try? FileManager.default.attributesOfItem(atPath: file.path),
              let date = attrs[.modificationDate] as? Date,
              Date().timeIntervalSince(date) < Self.genreDiskLifetime,
              let data = try? Data(contentsOf: file),
              let list = try? JSONDecoder().decode([SeriesSummary].self, from: data),
              !list.isEmpty else { return nil }
        return list
    }

    private func writeGenreToDisk(_ slug: String, _ list: [SeriesSummary]) {
        guard !list.isEmpty, let dir = genreDiskCache, let file = genreFile(slug),
              let data = try? JSONEncoder().encode(list) else { return }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try? data.write(to: file, options: .atomic)
    }

    public func allSeries() async throws -> [SeriesSummary] {
        let list = GenreParser.parseSeriesList(try await http.getText(url("/animes-alphabet")), baseURL: baseURL)
        return list.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    public func releaseCalendar() async throws -> [CalendarDay] {
        CalendarParser.parse(try await http.getText(url("/animekalender")), baseURL: baseURL)
    }

    /// No bundled skip times (the planned offline database never shipped); online times come from
    /// `onlineSkipTimes`, own times from the app's library.
    public func skipTimes(seriesTitle: String, seriesSlug: String, season: Int, episode: Int) async -> [SkipTime] {
        []
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
