import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Live implementation of `AniworldService` against aniworld.to.
/// TODO(Agent A): implement. Keep the public initializer signature.
public final class AniworldClient: AniworldService, @unchecked Sendable {
    public static let defaultBaseURL = URL(string: "https://aniworld.to")!
    public static let userAgent =
        "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1"

    public let baseURL: URL

    public init(baseURL: URL = AniworldClient.defaultBaseURL) {
        self.baseURL = baseURL
    }

    public func search(_ query: String) async throws -> [SeriesSummary] { fatalError("TODO") }
    public func seriesDetail(slug: String) async throws -> SeriesDetail { fatalError("TODO") }
    public func episodes(slug: String, season: Int) async throws -> [EpisodeRef] { fatalError("TODO") }
    public func hosters(for episode: EpisodeRef) async throws -> [HosterLink] { fatalError("TODO") }
    public func availableLanguages(_ hosters: [HosterLink], preferences: StreamPreferences) -> [StreamLanguage] { fatalError("TODO") }
    public func resolveStream(hosters: [HosterLink], language: StreamLanguage?, preferences: StreamPreferences,
                              verify: Bool, excluding: Set<String>) async throws -> ResolvedStream { fatalError("TODO") }
    public func homeSections() async throws -> [HomeSection] { fatalError("TODO") }
}
