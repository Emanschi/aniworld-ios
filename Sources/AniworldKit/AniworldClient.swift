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
    private let skipClient: AniSkipClient

    public convenience init(baseURL: URL = AniworldClient.defaultBaseURL) {
        self.init(baseURL: baseURL, http: HTTPClient(), extractors: .default)
    }

    init(baseURL: URL, http: HTTPClient, extractors: ExtractorRegistry, skipClient: AniSkipClient? = nil) {
        self.baseURL = baseURL
        self.http = http
        self.resolver = StreamResolver(http: http, extractors: extractors)
        self.skipClient = skipClient ?? AniSkipClient(transport: http)
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

    public func skipTimes(seriesTitle: String, seriesSlug: String, season: Int, episode: Int) async -> [SkipTime] {
        if let local = LocalSkipDatabase.shared.findSkipTimes(
            seriesSlug: seriesSlug,
            seriesTitle: seriesTitle,
            season: season,
            episode: episode
        ) {
            return local
        }
        return await skipClient.skipTimes(seriesTitle: seriesTitle, seriesSlug: seriesSlug, season: season, episode: episode)
    }
}
