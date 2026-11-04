import Foundation

/// Parses the `POST /ajax/search` JSON array (`{title, description, link}`).
///
/// The array mixes series roots (`/anime/stream/<slug>`), episode hits and support pages;
/// only series roots are kept and de-duplicated by slug.
enum SearchParser {
    static func parse(_ data: Data, query: String = "", baseURL: URL = AniworldClient.defaultBaseURL) -> [SeriesSummary] {
        guard let payload = try? JSONSerialization.jsonObject(with: data) as? [Any] else { return [] }
        return parse(payload.compactMap { $0 as? [String: Any] }, query: query, baseURL: baseURL)
    }

    /// The site ranks loosely, so series whose title contains `query` move to the front (stable).
    static func parse(_ payload: [[String: Any]], query: String = "",
                      baseURL: URL = AniworldClient.defaultBaseURL) -> [SeriesSummary] {
        var seen = Set<String>()
        var out: [SeriesSummary] = []
        for entry in payload {
            guard let link = entry["link"] as? String, let slug = seriesSlug(link),
                  seen.insert(slug).inserted,
                  let url = Support.absoluteURL(link, base: baseURL) else { continue }
            out.append(SeriesSummary(
                slug: slug,
                title: Support.cleanHTMLText(entry["title"] as? String ?? ""),
                url: url,
                description: Support.cleanHTMLText(entry["description"] as? String ?? "")))
        }
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !needle.isEmpty else { return out }
        return out.filter { $0.title.lowercased().contains(needle) } + out.filter { !$0.title.lowercased().contains(needle) }
    }

    /// The slug when `link` is exactly `/anime/stream/<slug>`.
    static func seriesSlug(_ link: String) -> String? {
        let parts = link.split(separator: "/").map(String.init)
        return parts.count == 3 && parts[0] == "anime" && parts[1] == "stream" ? parts[2] : nil
    }
}
