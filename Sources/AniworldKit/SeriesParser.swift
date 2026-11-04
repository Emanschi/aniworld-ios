import Foundation
import SwiftSoup

/// Series landing page and season pages.
///
/// The nav block `div#stream` lists the seasons (`/anime/stream/<slug>/staffel-<n>`, plus
/// `/filme` for films, modelled as season 0) and the episodes of the *active* season only.
enum SeriesParser {
    private static let languageTags: Set<String> = ["ger", "gersub", "gerdub", "eng", "engsub"]

    static func seasonPath(slug: String, season: Int) -> String {
        season == 0 ? "/anime/stream/\(slug)/filme" : "/anime/stream/\(slug)/staffel-\(season)"
    }

    private static func navHrefs(_ doc: Document) -> [String] {
        guard let anchors = try? doc.select("div#stream a[href]") else { return [] }
        return anchors.array().compactMap { try? Support.path(of: $0.attr("href")) }
    }

    /// Season numbers from the nav block (0 = films), films sorted last.
    static func parseSeasons(_ html: String, slug: String) -> [SeasonRef] {
        guard let doc = try? SwiftSoup.parse(html) else { return [] }
        let esc = NSRegularExpression.escapedPattern(for: slug)
        var found = Set<Int>()
        for href in navHrefs(doc) {
            if let m = Support.match("^/anime/stream/\(esc)/staffel-(\\d+)/?$", in: href), let n = Int(m[1]) {
                found.insert(n)
            } else if Support.match("^/anime/stream/\(esc)/filme/?$", in: href) != nil {
                found.insert(0)
            }
        }
        let numbered = found.filter { $0 > 0 }.sorted()
        return (numbered + (found.contains(0) ? [0] : [])).map(SeasonRef.init(number:))
    }

    /// Episodes of `season` from that season page's nav block and episode table. Deduped, sorted.
    static func parseEpisodes(_ html: String, slug: String, season: Int,
                              baseURL: URL = AniworldClient.defaultBaseURL) -> [EpisodeRef] {
        guard let doc = try? SwiftSoup.parse(html) else { return [] }
        let esc = NSRegularExpression.escapedPattern(for: slug)
        let pattern = season == 0
            ? "^/anime/stream/\(esc)/filme/film-(\\d+)/?$"
            : "^/anime/stream/\(esc)/staffel-\(season)/episode-(\\d+)/?$"
        let titles = episodeTitles(doc)
        var seen = Set<Int>()
        var out: [EpisodeRef] = []
        for href in navHrefs(doc) {
            guard let m = Support.match(pattern, in: href), let number = Int(m[1]), seen.insert(number).inserted,
                  let url = Support.absoluteURL(href, base: baseURL) else { continue }
            out.append(EpisodeRef(seriesSlug: slug, season: season, number: number,
                                  title: titles[href] ?? "", url: url))
        }
        return out.sorted { $0.number < $1.number }
    }

    /// path -> display title from `td.seasonEpisodeTitle` (German title, else the original one).
    private static func episodeTitles(_ doc: Document) -> [String: String] {
        var out: [String: String] = [:]
        guard let anchors = try? doc.select("td.seasonEpisodeTitle a[href]") else { return out }
        for a in anchors.array() {
            guard let href = try? a.attr("href") else { continue }
            let strong = (try? a.select("strong").first()?.text()) ?? ""
            let span = (try? a.select("span").first()?.text()) ?? ""
            let title = strong.isEmpty ? span : strong
            if !title.isEmpty { out[Support.path(of: href)] = title }
        }
        return out
    }

    /// Full series page: title, description, cover, backdrop, genres, years, seasons.
    static func parseDetail(_ html: String, slug: String,
                            baseURL: URL = AniworldClient.defaultBaseURL) throws -> SeriesDetail {
        let doc = try SwiftSoup.parse(html)
        guard let title = try doc.select("div.series-title h1 span, h1[itemprop=name]").first()?.text(),
              !title.isEmpty else {
            throw AniworldError.parsing("series page has no title")
        }
        var description = ""
        if let p = try doc.select("p.seri_des").first() {
            description = try p.attr("data-full-description")
            if description.isEmpty { description = try p.text() }
        }
        description = Support.cleanHTMLText(description)

        let cover = Support.imageSource(try doc.select(".seriesCoverBox img").first())
            .flatMap { Support.absoluteURL($0, base: baseURL) }

        var backdrop: URL?
        if let style = try doc.select(".backdrop").first()?.attr("style"),
           let m = Support.match("url\\(['\"]?([^'\")]+)['\"]?\\)", in: style) {
            backdrop = Support.absoluteURL(m[1], base: baseURL)
        }

        var genres: [String] = []
        for a in try doc.select(".genres a.genreButton, .genres a[itemprop=genre]").array() {
            let g = try a.text()
            // The site lists audio/subtitle availability ("Ger", "GerSub", ...) as pseudo-genres.
            if languageTags.contains(g.lowercased()) { continue }
            if !g.isEmpty, !genres.contains(g) { genres.append(g) }
        }

        func year(_ prop: String) -> Int? {
            guard let text = try? doc.select("[itemprop=\(prop)]").first()?.text() else { return nil }
            return Support.match("(\\d{4})", in: text).flatMap { Int($0[1]) }
        }

        let url = Support.absoluteURL("/anime/stream/\(slug)", base: baseURL)!
        let summary = SeriesSummary(slug: slug, title: title, url: url, description: description, coverURL: cover)
        return SeriesDetail(summary: summary, description: description, coverURL: cover, backdropURL: backdrop,
                            genres: genres, startYear: year("startDate"), endYear: year("endDate"),
                            seasons: parseSeasons(html, slug: slug))
    }
}
