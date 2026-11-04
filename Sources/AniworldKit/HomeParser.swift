import Foundation
import SwiftSoup

/// Start page rows: `div.pageTitle15 > h2` followed by `div.previews` holding `.coverListItem`s.
/// Rows without items are dropped; layout surprises yield fewer (or no) sections.
enum HomeParser {
    static func parse(_ html: String, baseURL: URL = AniworldClient.defaultBaseURL) -> [HomeSection] {
        guard let doc = try? SwiftSoup.parse(html), let headers = try? doc.select("div.pageTitle15") else { return [] }
        var sections: [HomeSection] = []
        for header in headers.array() {
            guard let title = try? header.select("h2").first()?.text(), !title.isEmpty,
                  let previews = try? header.nextElementSibling(), previews.hasClass("previews") else { continue }
            var seen = Set<String>()
            var items: [SeriesSummary] = []
            for item in (try? previews.select(".coverListItem").array()) ?? [] {
                guard let a = try? item.select("a[href]").first(),
                      let slug = SearchParser.seriesSlug(Support.path(of: (try? a.attr("href")) ?? "")),
                      seen.insert(slug).inserted,
                      let url = Support.absoluteURL("/anime/stream/\(slug)", base: baseURL) else { continue }
                let name = (try? a.select("h3").first()?.text()) ?? ""
                let genre = (try? a.select("small").first()?.text()) ?? ""
                let cover = Support.imageSource(try? a.select("img").first())
                    .flatMap { Support.absoluteURL($0, base: baseURL) }
                items.append(SeriesSummary(slug: slug, title: name.isEmpty ? slug : name, url: url,
                                           description: genre, coverURL: cover))
            }
            if !items.isEmpty { sections.append(HomeSection(title: title, items: items)) }
        }
        return sections
    }
}
