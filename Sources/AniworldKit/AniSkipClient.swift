import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Resolves anime titles to MyAnimeList IDs and queries AniSkip API v2 for intro/outro/recap intervals.
public final class AniSkipClient: Sendable {
    private let transport: HTTPFetching

    private actor Cache {
        var malIds: [String: Int] = [:]
        var skipTimes: [String: [SkipTime]] = [:]

        func malId(for key: String) -> Int? { malIds[key] }
        func setMalId(_ id: Int, for key: String) { malIds[key] = id }

        func skips(for key: String) -> [SkipTime]? { skipTimes[key] }
        func setSkips(_ list: [SkipTime], for key: String) { skipTimes[key] = list }
    }

    private let cache = Cache()

    public init(transport: HTTPFetching) {
        self.transport = transport
    }

    /// Fetches skip intervals for an episode. Returns empty array if not found or on error.
    public func skipTimes(seriesTitle: String, seriesSlug: String, season: Int, episode: Int) async -> [SkipTime] {
        guard episode > 0 else { return [] }

        guard let malId = await resolveMalId(seriesTitle: seriesTitle, seriesSlug: seriesSlug, season: season) else {
            return []
        }

        let cacheKey = "\(malId)-s\(season)e\(episode)"
        if let cached = await cache.skips(for: cacheKey) {
            return cached
        }

        let results = await fetchSkipTimes(malId: malId, episode: episode)
        await cache.setSkips(results, for: cacheKey)
        return results
    }

    // MARK: - MAL ID Resolution

    private func resolveMalId(seriesTitle: String, seriesSlug: String, season: Int) async -> Int? {
        let cleanTitle = seriesTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let cacheKey = "\(cleanTitle.lowercased())-s\(season)"
        if let cached = await cache.malId(for: cacheKey) {
            return cached
        }

        // Generate query variations (with season for season > 1, clean title, slug words)
        var queries: [String] = []
        if season > 1 {
            queries.append("\(cleanTitle) Season \(season)")
            queries.append("\(cleanTitle) \(season)")
        }
        queries.append(cleanTitle)

        let slugWords = seriesSlug.replacingOccurrences(of: "-", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if !slugWords.isEmpty && slugWords.lowercased() != cleanTitle.lowercased() {
            if season > 1 {
                queries.append("\(slugWords) Season \(season)")
                queries.append("\(slugWords) \(season)")
            }
            queries.append(slugWords)
        }

        for query in queries {
            if let id = await queryAniList(search: query) {
                await cache.setMalId(id, for: cacheKey)
                return id
            }
            if let id = await queryMyAnimeListPrefix(search: query) {
                await cache.setMalId(id, for: cacheKey)
                return id
            }
        }

        return nil
    }

    /// Queries AniList GraphQL API to find the MyAnimeList ID (`idMal`).
    private func queryAniList(search: String) async -> Int? {
        guard let url = URL(string: "https://graphql.anilist.co") else { return nil }

        let graphQLQuery = """
        query ($search: String) {
          Media(search: $search, type: ANIME) {
            idMal
          }
        }
        """

        let bodyObject: [String: Any] = [
            "query": graphQLQuery,
            "variables": ["search": search]
        ]

        guard let httpBody = try? JSONSerialization.data(withJSONObject: bodyObject) else { return nil }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = httpBody

        do {
            let response = try await transport.send(request)
            guard response.status == 200 else { return nil }

            guard let json = try? JSONSerialization.jsonObject(with: response.data) as? [String: Any],
                  let data = json["data"] as? [String: Any],
                  let media = data["Media"] as? [String: Any],
                  let idMal = media["idMal"] as? Int, idMal > 0 else {
                return nil
            }
            return idMal
        } catch {
            return nil
        }
    }

    /// Fallback prefix search against MyAnimeList.
    private func queryMyAnimeListPrefix(search: String) async -> Int? {
        var components = URLComponents(string: "https://myanimelist.net/search/prefix.json")
        components?.queryItems = [
            URLQueryItem(name: "type", value: "anime"),
            URLQueryItem(name: "keyword", value: search)
        ]
        guard let url = components?.url else { return nil }

        var request = URLRequest(url: url)
        request.setValue(
            "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1",
            forHTTPHeaderField: "User-Agent"
        )
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        do {
            let response = try await transport.send(request)
            guard response.status == 200 else { return nil }

            guard let json = try? JSONSerialization.jsonObject(with: response.data) as? [String: Any],
                  let categories = json["categories"] as? [[String: Any]] else {
                return nil
            }

            for category in categories {
                guard (category["type"] as? String) == "anime",
                      let items = category["items"] as? [[String: Any]],
                      let first = items.first,
                      let id = first["id"] as? Int, id > 0 else {
                    continue
                }
                return id
            }
            return nil
        } catch {
            return nil
        }
    }

    // MARK: - AniSkip API Query

    private func fetchSkipTimes(malId: Int, episode: Int) async -> [SkipTime] {
        var components = URLComponents(string: "https://api.aniskip.com/v2/skip-times/\(malId)/\(episode)")
        components?.queryItems = [
            URLQueryItem(name: "types", value: "op"),
            URLQueryItem(name: "types", value: "ed"),
            URLQueryItem(name: "types", value: "mixed-op"),
            URLQueryItem(name: "types", value: "mixed-ed"),
            URLQueryItem(name: "types", value: "recap"),
            URLQueryItem(name: "episodeLength", value: "0")
        ]
        guard let url = components?.url else { return [] }

        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(
            "AniworldIOS/1.0 (iOS; dxmoc/aniworld-cli port)",
            forHTTPHeaderField: "User-Agent"
        )

        do {
            let response = try await transport.send(request)
            guard response.status == 200 else { return [] }

            let decoded = try JSONDecoder().decode(AniSkipAPIResponse.self, from: response.data)
            guard decoded.found else { return [] }

            let times = decoded.results.compactMap { item -> SkipTime? in
                guard let skipType = SkipType(rawValue: item.skipType) else { return nil }
                guard item.interval.endTime > item.interval.startTime, item.interval.startTime >= 0 else {
                    return nil
                }
                return SkipTime(
                    skipId: item.skipId,
                    skipType: skipType,
                    interval: SkipInterval(
                        startTime: item.interval.startTime,
                        endTime: item.interval.endTime
                    ),
                    episodeLength: item.episodeLength ?? 0
                )
            }

            return times.sorted { $0.interval.startTime < $1.interval.startTime }
        } catch {
            return []
        }
    }
}

// MARK: - API Decodables

private struct AniSkipAPIResponse: Decodable {
    var found: Bool
    var results: [AniSkipItem]
}

private struct AniSkipItem: Decodable {
    var interval: AniSkipInterval
    var skipType: String
    var skipId: String
    var episodeLength: Double?
}

private struct AniSkipInterval: Decodable {
    var startTime: Double
    var endTime: Double
}
