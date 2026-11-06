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
            // One entry per series and day; the site lists every language as its own item.
            var order: [String] = []
            var groups: [String: (series: SeriesSummary, releases: [CalendarRelease])] = [:]
            for a in anchors.array() {
                guard let href = try? a.attr("href") else { continue }
                let path = Support.path(of: href)
                let parts = path.split(separator: "/").map(String.init)
                guard parts.count >= 3, parts[0] == "anime", parts[1] == "stream" else { continue }
                let slug = parts[2]
                let id = "\(title)|/anime/stream/\(slug)"
                let release = self.release(for: a)
                if var group = groups[id] {
                    if !group.releases.contains(release) { group.releases.append(release) }
                    groups[id] = group
                    continue
                }
                guard let url = Support.absoluteURL("/anime/stream/\(slug)", base: baseURL) else { continue }
                let name = ((try? a.select("h3").first()?.text()) ?? "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                let cover = Support.imageSource(try? a.select("img").first())
                    .flatMap { Support.absoluteURL($0, base: baseURL) }
                let series = SeriesSummary(slug: slug, title: name.isEmpty ? slug : name, url: url, coverURL: cover)
                order.append(id)
                groups[id] = (series, [release])
            }
            let entries = order.compactMap { id -> CalendarEntry? in
                guard let group = groups[id] else { return nil }
                let releases = sorted(group.releases)
                return CalendarEntry(id: id, series: group.series, info: info(for: releases), releases: releases)
            }
            if !entries.isEmpty { days.append(CalendarDay(title: title, entries: entries, date: date(in: title))) }
        }
        return days
    }

    /// Start of the day named in a heading like "Donnerstag, 05.11.2026 (heute)".
    static func date(in title: String, calendar: Calendar = .current) -> Date? {
        guard let m = Support.match("(\\d{1,2})\\.(\\d{1,2})\\.(\\d{4})", in: title),
              let d = Int(m[1]), let mo = Int(m[2]), let y = Int(m[3]) else { return nil }
        return calendar.date(from: DateComponents(year: y, month: mo, day: d))
    }

    /// Code, time and language of one calendar item.
    private static func release(for anchor: Element) -> CalendarRelease {
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
        var language: StreamLanguage?
        for img in (try? anchor.select("img.flag").array()) ?? [] {
            language = EpisodeParser.classifyLanguage(
                (try? img.attr("data-src")) ?? "", (try? img.attr("src")) ?? "",
                (try? img.attr("alt")) ?? "", (try? img.attr("title")) ?? "")
            if language != nil { break }
        }
        return CalendarRelease(code: code, language: language, time: time)
    }

    /// German dub, German sub, English sub, unknown last; within a language by (season, episode)
    /// parsed from the code, then time. Unparsable codes keep their original order.
    private static func sorted(_ releases: [CalendarRelease]) -> [CalendarRelease] {
        func rank(_ l: StreamLanguage?) -> Int {
            switch l {
            case .germanDub: 0
            case .germanSub: 1
            case .englishSub: 2
            case nil: 3
            }
        }
        func key(_ r: CalendarRelease) -> (season: Int, episode: Int, time: String) {
            guard let m = Support.match("^S(\\d+)E(\\d+)$", in: r.code.uppercased()),
                  let s = Int(m[1]), let e = Int(m[2]) else { return (Int.max, Int.max, "") }
            return (s, e, r.time)
        }
        return releases.enumerated()
            .sorted { a, b in
                let ra = rank(a.element.language), rb = rank(b.element.language)
                if ra != rb { return ra < rb }
                let ka = key(a.element), kb = key(b.element)
                if ka.season != kb.season { return ka.season < kb.season }
                if ka.episode != kb.episode { return ka.episode < kb.episode }
                if ka.time != kb.time { return ka.time < kb.time }
                return a.offset < b.offset
            }
            .map(\.element)
    }

    /// "S01E02 GerDub · S01E05 GerSub/EngSub · 17:10": releases with the same code and time are
    /// merged unless one is the German dub (a dub is never merged with a sub, like in the UI);
    /// the time is appended once if all groups share it, else after each group.
    static func info(for releases: [CalendarRelease]) -> String {
        var groups: [(code: String, time: String, isDub: Bool, langs: [String])] = []
        for r in releases {
            let lang = r.language?.shortName
            let isDub = r.language == .germanDub
            if let i = groups.firstIndex(where: { $0.code == r.code && $0.time == r.time && $0.isDub == isDub }) {
                if let lang, !groups[i].langs.contains(lang) { groups[i].langs.append(lang) }
            } else {
                groups.append((r.code, r.time, isDub, lang.map { [$0] } ?? []))
            }
        }
        let times = Set(groups.map(\.time))
        let shared = times.count == 1 ? (times.first ?? "") : nil
        var parts = groups.map { g -> String in
            var p = [g.code, g.langs.joined(separator: "/")]
            if shared == nil { p.append(g.time) }
            return p.filter { !$0.isEmpty }.joined(separator: " ")
        }
        if let shared, !shared.isEmpty { parts.append(shared) }
        return parts.filter { !$0.isEmpty }.joined(separator: " · ")
    }
}
