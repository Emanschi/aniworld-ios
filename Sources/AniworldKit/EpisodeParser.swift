import Foundation
import SwiftSoup

/// Episode page: the language switch and the hoster list.
///
/// `div.changeLanguageBox` has flag `<img data-lang-key>`s; the key -> language mapping is
/// read off the flag's src/alt/title, never hardcoded. Each hoster `<li>` carries
/// `data-lang-key`, `data-link-target="/redirect/<id>"` and an `<h4>` name.
enum EpisodeParser {
    /// Order matters: the subtitle variants also contain "german"/"deutsch"
    /// (`japanese-german.svg`, "mit Untertitel Deutsch"), so they are tested before plain dub.
    static func classifyLanguage(_ texts: String...) -> StreamLanguage? {
        let blob = texts.filter { !$0.isEmpty }.joined(separator: " ").lowercased()
        if blob.contains("japanese-german") || blob.contains("untertitel deutsch") || blob.contains("ger-sub") {
            return .germanSub
        }
        if blob.contains("japanese-english") || blob.contains("untertitel englisch")
            || blob.contains("english") || blob.contains("englisch") {
            return .englishSub
        }
        if blob.contains("german") || blob.contains("deutsch") { return .germanDub }
        return nil
    }

    /// lang-key -> language; flags that cannot be classified map to nil.
    static func parseLanguageMap(_ html: String) -> [Int: StreamLanguage?] {
        guard let doc = try? SwiftSoup.parse(html),
              let imgs = try? doc.select(".changeLanguageBox img[data-lang-key]") else { return [:] }
        var map: [Int: StreamLanguage?] = [:]
        for img in imgs.array() {
            guard let key = Int((try? img.attr("data-lang-key")) ?? "") else { continue }
            map[key] = classifyLanguage((try? img.attr("src")) ?? "", (try? img.attr("alt")) ?? "",
                                        (try? img.attr("title")) ?? "")
        }
        return map
    }

    static func parseHosters(_ html: String, baseURL: URL = AniworldClient.defaultBaseURL) -> [HosterLink] {
        guard let doc = try? SwiftSoup.parse(html),
              let items = try? doc.select("li[data-link-target][data-lang-key]") else { return [] }
        let langMap = parseLanguageMap(html)
        var out: [HosterLink] = []
        for li in items.array() {
            guard let target = try? li.attr("data-link-target"), target.hasPrefix("/redirect/"),
                  let key = Int((try? li.attr("data-lang-key")) ?? ""),
                  let name = try? li.select("h4").first()?.text().trimmingCharacters(in: .whitespacesAndNewlines),
                  !name.isEmpty,
                  let url = Support.absoluteURL(target, base: baseURL) else { continue }
            out.append(HosterLink(name: name, language: langMap[key] ?? nil, languageKey: key, redirectURL: url))
        }
        return out
    }
}
