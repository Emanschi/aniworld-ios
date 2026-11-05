import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Online intro/outro/recap times from the public AniSkip API (api.aniskip.com).
///
/// AniSkip is keyed by MyAnimeList IDs, which aniworld.to does not expose, so the series title is
/// first mapped to a MAL ID via AniList's public GraphQL API. Nothing is bundled; every failure
/// (offline, no match, rate limit) simply yields no times.
final class OnlineSkipClient: Sendable {
    private let transport: HTTPFetching
    private let cache = Cache()

    init(transport: HTTPFetching) {
        self.transport = transport
    }

    private actor Cache {
        /// title key -> MAL id (0 = looked up, nothing found)
        var malIds: [String: Int] = [:]
        var skips: [String: [SkipTime]] = [:]
        func malId(_ key: String) -> Int? { malIds[key] }
        func setMalId(_ id: Int, _ key: String) { malIds[key] = id }
        func skipTimes(_ key: String) -> [SkipTime]? { skips[key] }
        func setSkipTimes(_ list: [SkipTime], _ key: String) { skips[key] = list }
    }

    func skipTimes(seriesTitle: String, seriesSlug: String, season: Int, episode: Int) async -> [SkipTime] {
        // Films (season 0) are separate MAL entries without reliable numbering.
        guard season > 0, episode > 0 else { return [] }
        guard let malId = await resolveMalId(title: seriesTitle, slug: seriesSlug, season: season) else { return [] }
        let key = "\(malId)|\(episode)"
        if let cached = await cache.skipTimes(key) { return cached }
        guard let times = await fetchSkipTimes(malId: malId, episode: episode) else { return [] }
        await cache.setSkipTimes(times, key)
        return times
    }

    // MARK: MAL ID

    /// Search queries for a season. Seasons > 1 are separate MAL entries, so they never fall back to the
    /// plain title (that would return times of season 1).
    static func queries(title: String, slug: String, season: Int) -> [String] {
        let clean = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let slugWords = slug.replacingOccurrences(of: "-", with: " ").trimmingCharacters(in: .whitespaces)
        var bases = [clean]
        if !slugWords.isEmpty, slugWords.lowercased() != clean.lowercased() { bases.append(slugWords) }
        bases = bases.filter { !$0.isEmpty }
        var out: [String] = []
        for base in bases {
            if season > 1 {
                out.append("\(base) Season \(season)")
                out.append("\(base) \(season)")
            } else {
                out.append(base)
            }
        }
        return out
    }

    private func resolveMalId(title: String, slug: String, season: Int) async -> Int? {
        let key = "\(slug.lowercased())|s\(season)"
        if let cached = await cache.malId(key) { return cached > 0 ? cached : nil }
        for query in Self.queries(title: title, slug: slug, season: season) {
            switch await queryAniList(search: query) {
            case .found(let id):
                await cache.setMalId(id, key)
                return id
            case .notFound:
                continue
            case .failed:
                return nil // network/rate limit: don't cache, try again next time
            }
        }
        await cache.setMalId(0, key)
        return nil
    }

    enum LookupResult: Equatable { case found(Int), notFound, failed }

    private func queryAniList(search: String) async -> LookupResult {
        guard let url = URL(string: "https://graphql.anilist.co") else { return .failed }
        let query = "query ($search: String) { Media(search: $search, type: ANIME) { idMal } }"
        let body: [String: Any] = ["query": query, "variables": ["search": search]]
        guard let data = try? JSONSerialization.data(withJSONObject: body) else { return .failed }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = data
        guard let response = try? await transport.send(request) else { return .failed }
        return Self.parseAniList(status: response.status, data: response.data)
    }

    /// AniList answers 404 with `"Media": null` when nothing matches.
    static func parseAniList(status: Int, data: Data) -> LookupResult {
        guard status == 200 || status == 404 else { return .failed }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return status == 404 ? .notFound : .failed
        }
        guard let payload = json["data"] as? [String: Any],
              let media = payload["Media"] as? [String: Any],
              let id = (media["idMal"] as? NSNumber)?.intValue, id > 0 else { return .notFound }
        return .found(id)
    }

    // MARK: Skip times

    private func fetchSkipTimes(malId: Int, episode: Int) async -> [SkipTime]? {
        var components = URLComponents(string: "https://api.aniskip.com/v2/skip-times/\(malId)/\(episode)")
        components?.queryItems = ["op", "ed", "mixed-op", "mixed-ed", "recap"].map {
            URLQueryItem(name: "types", value: $0)
        } + [URLQueryItem(name: "episodeLength", value: "0")]
        guard let url = components?.url else { return nil }
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        guard let response = try? await transport.send(request) else { return nil }
        return Self.parseSkipTimes(status: response.status, data: response.data)
    }

    /// AniSkip answers 404 with `found: false` when no times exist. nil = request failed (don't cache).
    static func parseSkipTimes(status: Int, data: Data) -> [SkipTime]? {
        guard status == 200 || status == 404 else { return nil }
        guard let decoded = try? JSONDecoder().decode(APIResponse.self, from: data) else {
            return status == 404 ? [] : nil
        }
        guard decoded.found else { return [] }
        return (decoded.results ?? []).compactMap { item -> SkipTime? in
            guard let type = SkipType(rawValue: item.skipType),
                  item.interval.startTime >= 0, item.interval.endTime > item.interval.startTime else { return nil }
            return SkipTime(skipId: "aniskip-\(item.skipId)", skipType: type,
                            interval: SkipInterval(startTime: item.interval.startTime, endTime: item.interval.endTime),
                            episodeLength: item.episodeLength ?? 0)
        }
        .sorted { $0.interval.startTime < $1.interval.startTime }
    }

    private struct APIResponse: Decodable {
        var found: Bool
        var results: [Item]?
    }

    private struct Item: Decodable {
        var interval: Interval
        var skipType: String
        var skipId: String
        var episodeLength: Double?
    }

    private struct Interval: Decodable {
        var startTime: Double
        var endTime: Double
    }
}
