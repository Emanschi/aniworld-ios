import Foundation
import SwiftSoup

/// `/animekalender`: one `section.calendarList` per day (`h3` = "Donnerstag, 05.11.2026 (heute)"),
/// each with cover items linking to `/anime/stream/<slug>/staffel-<n>/episode-<m>`.
/// The first `small` holds the episode code, a later one the time ("~ 13:40 Uhr").
enum CalendarParser {
    static func parse(_ html: String, baseURL: URL = AniworldClient.defaultBaseURL) -> [CalendarDay] {
        guard let doc = try? SwiftSoup.parse(html), let sections = try? doc.select("section.calendarList") else {
            return []
        }
        var days: [CalendarDay] = []
        for section in sections.array() {
            let title = ((try? section.select("h3").first()?.text()) ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty, let anchors = try? section.select(".seriesListContainer a[href]") else { continue }
            var entries: [CalendarEntry] = []
            var seenIDs = Set<String>()
            for a in anchors.array() {
                guard let href = try? a.attr("href") else { continue }
                let path = Support.path(of: href)
                let parts = path.split(separator: "/").map(String.init)
                guard parts.count >= 3, parts[0] == "anime", parts[1] == "stream" else { continue }
                let slug = parts[2]
                let id = "\(title)|\(path)"
                guard seenIDs.insert(id).inserted,
                      let url = Support.absoluteURL("/anime/stream/\(slug)", base: baseURL) else { continue }
                let name = ((try? a.select("h3").first()?.text()) ?? "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                let cover = Support.imageSource(try? a.select("img").first())
                    .flatMap { Support.absoluteURL($0, base: baseURL) }
                let series = SeriesSummary(slug: slug, title: name.isEmpty ? slug : name, url: url, coverURL: cover)
                entries.append(CalendarEntry(id: id, series: series, info: info(for: a)))
            }
            if !entries.isEmpty { days.append(CalendarDay(title: title, entries: entries)) }
        }
        return days
    }

    /// "S01E06 · 13:40" from the item's `small` texts (either part may be missing).
    private static func info(for anchor: Element) -> String {
        var code = ""
        var time = ""
        for small in (try? anchor.select("small").array()) ?? [] {
            let text = ((try? small.text()) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if code.isEmpty, let m = Support.match("(S\\d+E\\d+)", in: text, options: [.caseInsensitive]) {
                code = m[1].uppercased()
            }
            if time.isEmpty, let m = Support.match("(\\d{1,2}:\\d{2})", in: text) {
                time = m[1]
            }
        }
        return [code, time].filter { !$0.isEmpty }.joined(separator: " · ")
    }
}
