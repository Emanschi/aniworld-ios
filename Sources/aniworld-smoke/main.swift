import Foundation
import AniworldKit

/// Live end-to-end check: search -> detail -> episodes -> hosters -> resolveStream.
func short(_ url: URL?) -> String {
    guard let s = url?.absoluteString else { return "nil" }
    return s.count > 90 ? String(s.prefix(90)) + "…" : s
}

func run() async throws {
    let client = AniworldClient()

    let home = try await client.homeSections()
    print("home: \(home.map { "\($0.title) (\($0.items.count))" }.joined(separator: ", "))")
    if let first = home.first?.items.first { print("  first: \(first.title) cover=\(short(first.coverURL))") }

    let results = try await client.search("naruto")
    print("search: \(results.count) results; first 3: \(results.prefix(3).map(\.title))")
    guard let naruto = results.first(where: { $0.slug == "naruto" }) ?? results.first else { throw AniworldError.parsing("no results") }

    let detail = try await client.seriesDetail(slug: naruto.slug)
    print("detail: \(detail.summary.title) \(detail.startYear.map(String.init) ?? "?")-\(detail.endYear.map(String.init) ?? "?")")
    print("  genres: \(detail.genres)  seasons: \(detail.seasons.map(\.number))")
    print("  cover: \(short(detail.coverURL))  backdrop: \(short(detail.backdropURL))")
    print("  description: \(detail.description.prefix(80))… (\(detail.description.count) chars)")

    let episodes = try await client.episodes(slug: naruto.slug, season: 1)
    print("episodes S1: \(episodes.count); first: \(episodes.first.map { "\($0.code) \($0.title)" } ?? "-")")
    guard let episode = episodes.first else { throw AniworldError.parsing("no episodes") }

    let hosters = try await client.hosters(for: episode)
    print("hosters E1: \(hosters.map { "\($0.name)/\($0.language?.shortName ?? "?")" })")
    print("languages: \(client.availableLanguages(hosters, preferences: .default).map(\.shortName))")

    let stream = try await client.resolveStream(hosters: hosters)
    print("stream: \(stream.hoster) \(stream.language?.shortName ?? "?") \(short(stream.url))")
    print("  headers: \(stream.headers.mapValues { short(URL(string: $0)) == "nil" ? $0 : $0 })")
}

do {
    try await run()
    print("OK")
} catch {
    print("FAILED: \(error)")
    exit(1)
}
