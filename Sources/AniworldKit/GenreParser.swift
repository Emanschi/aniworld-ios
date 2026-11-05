import Foundation
import SwiftSoup

/// Genre index (links `/genre/<slug>` on the start page), genre listing pages (`/genre/<slug>[/<page>]`)
/// and the full series lists (`/animes`, `/animes-alphabet`).
enum GenreParser {
    /// Audio/subtitle availability that the site lists as pseudo-genres.
    static let languageSlugs: Set<String> = ["ger", "gersub", "gerdub", "eng", "engsub", "engdub"]

    /// A genre for an `href` of the form `/genre/<slug>` (absolute or relative); nil for language
    /// pseudo-genres, pagination links (`/genre/<slug>/2`) and anything else.
    static func genreRef(href: String, name: String) -> GenreRef? {
        let path = Support.path(of: href.trimmingCharacters(in: .whitespacesAndNewlines))
        let parts = path.split(separator: "/").map(String.init)
        guard parts.count == 2, parts[0] == "genre" else { return nil }
        let slug = parts[1]
        guard !slug.isEmpty, !languageSlugs.contains(slug.lowercased()) else { return nil }
        let cleaned = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return GenreRef(slug: slug, name: cleaned.isEmpty ? slug : cleaned)
    }

    /// All distinct genres linked on the page, in page order, without language pseudo-genres.
    static func parseGenres(_ html: String) -> [GenreRef] {
        guard let doc = try? SwiftSoup.parse(html), let anchors = try? doc.select("a[href]") else { return [] }
        var seen = Set<String>()
        var out: [GenreRef] = []
        for a in anchors.array() {
            guard let href = try? a.attr("href"),
                  let ref = genreRef(href: href, name: (try? a.text()) ?? ""),
                  seen.insert(ref.slug).inserted else { continue }
            out.append(ref)
        }
        return out
    }

    /// Highest page number linked from the pagination of a genre page (1 when there is none).
    static func lastPage(_ html: String, slug: String) -> Int {
        guard let doc = try? SwiftSoup.parse(html), let anchors = try? doc.select("a[href]") else { return 1 }
        var last = 1
        for a in anchors.array() {
            guard let href = try? a.attr("href") else { continue }
            let parts = Support.path(of: href).split(separator: "/").map(String.init)
            if parts.count == 3, parts[0] == "genre", parts[1] == slug, let n = Int(parts[2]), n > last { last = n }
        }
        return last
    }

    /// Series of a genre page: cover grid `div.seriesListContainer` with `a[href=/anime/stream/<slug>]`
    /// holding `h3` (title), `small` (genre) and a lazy-loaded cover image.
    static func parseGenrePage(_ html: String, baseURL: URL = AniworldClient.defaultBaseURL) -> [SeriesSummary] {
        guard let doc = try? SwiftSoup.parse(html), let anchors = try? doc.select(".seriesListContainer a[href]") else {
            return []
        }
        var seen = Set<String>()
        var out: [SeriesSummary] = []
        for a in anchors.array() {
            guard let href = try? a.attr("href"),
                  let slug = SearchParser.seriesSlug(Support.path(of: href)),
                  seen.insert(slug).inserted,
                  let url = Support.absoluteURL("/anime/stream/\(slug)", base: baseURL) else { continue }
            let title = (try? a.select("h3").first()?.text()) ?? ""
            let genre = (try? a.select("small").first()?.text()) ?? ""
            let cover = Support.imageSource(try? a.select("img").first()).flatMap { Support.absoluteURL($0, base: baseURL) }
            out.append(SeriesSummary(slug: slug, title: title.isEmpty ? slug : title, url: url,
                                     description: genre, coverURL: cover))
        }
        return out
    }

    /// URL-style genre slug for a genre heading, matching the site's `/genre/<slug>` links
    /// ("Fighting-Shounen" → "fighting-shounen", "Komödie" → "komoedie", "Slice of Life" → "slice-of-life").
    static func slugify(_ name: String) -> String {
        var s = name.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        for (from, to) in [("ä", "ae"), ("ö", "oe"), ("ü", "ue"), ("ß", "ss")] {
            s = s.replacingOccurrences(of: from, with: to)
        }
        s = s.folding(options: .diacriticInsensitive, locale: Locale(identifier: "en_US_POSIX"))
        s = s.replacingOccurrences(of: "[^a-z0-9]+", with: "-", options: .regularExpression)
        return s.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    }

    /// `/animes` groups every series by genre: `div.genre` with an `h3` heading and a `ul` of links.
    /// Returns slugified heading → series of that genre (one request instead of paging `/genre/<slug>`).
    static func parseGenreGroups(_ html: String, baseURL: URL = AniworldClient.defaultBaseURL) -> [String: [SeriesSummary]] {
        guard let doc = try? SwiftSoup.parse(html), let blocks = try? doc.select("#seriesContainer div.genre") else {
            return [:]
        }
        var out: [String: [SeriesSummary]] = [:]
        for block in blocks.array() {
            guard let heading = try? block.select("h3").first()?.text() else { continue }
            let key = slugify(heading)
            guard !key.isEmpty, let anchors = try? block.select("li a[href]") else { continue }
            var seen = Set<String>()
            var list: [SeriesSummary] = []
            for a in anchors.array() {
                guard let href = try? a.attr("href"),
                      let slug = SearchParser.seriesSlug(Support.path(of: href)),
                      seen.insert(slug).inserted,
                      let url = Support.absoluteURL("/anime/stream/\(slug)", base: baseURL) else { continue }
                let title = ((try? a.text()) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                list.append(SeriesSummary(slug: slug, title: title.isEmpty ? slug : title, url: url))
            }
            out[key, default: []].append(contentsOf: list)
        }
        return out
    }

    /// Plain list pages (`/animes`, `/animes-alphabet`): `div.genre > ul > li > a`. De-duplicated by slug
    /// (on `/animes` a series appears once per genre).
    static func parseSeriesList(_ html: String, baseURL: URL = AniworldClient.defaultBaseURL) -> [SeriesSummary] {
        guard let doc = try? SwiftSoup.parse(html), let anchors = try? doc.select("#seriesContainer li a[href]") else {
            return []
        }
        var seen = Set<String>()
        var out: [SeriesSummary] = []
        for a in anchors.array() {
            guard let href = try? a.attr("href"),
                  let slug = SearchParser.seriesSlug(Support.path(of: href)),
                  seen.insert(slug).inserted,
                  let url = Support.absoluteURL("/anime/stream/\(slug)", base: baseURL) else { continue }
            let title = ((try? a.text()) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            out.append(SeriesSummary(slug: slug, title: title.isEmpty ? slug : title, url: url))
        }
        return out
    }
}
