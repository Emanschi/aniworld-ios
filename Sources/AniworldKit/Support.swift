import Foundation
import SwiftSoup

enum Support {
    /// Resolves a (possibly relative) link against `base`.
    static func absoluteURL(_ link: String, base: URL) -> URL? {
        URL(string: link.trimmingCharacters(in: .whitespacesAndNewlines), relativeTo: base)?.absoluteURL
    }

    /// The path of a relative or absolute link, without query/fragment.
    static func path(of href: String) -> String {
        if href.hasPrefix("/") {
            return href.split(whereSeparator: { $0 == "?" || $0 == "#" }).first.map(String.init) ?? href
        }
        return URL(string: href)?.path ?? href
    }

    /// Strips tags (e.g. the `<em>` search highlight) and decodes HTML entities.
    static func cleanHTMLText(_ text: String) -> String {
        let stripped = text.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        let decoded = (try? Parser.unescapeEntities(stripped, false)) ?? stripped
        return decoded.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Lazy-loaded image source; skips the 1x1 `data:` placeholder.
    static func imageSource(_ img: Element?) -> String? {
        guard let img else { return nil }
        for attr in ["data-src", "src"] {
            if let value = try? img.attr(attr), !value.isEmpty, !value.hasPrefix("data:") { return value }
        }
        return nil
    }

    /// `scheme://host[:port]` of a URL.
    static func origin(of url: URL) -> String {
        guard let scheme = url.scheme, let host = url.host else { return "" }
        if let port = url.port { return "\(scheme)://\(host):\(port)" }
        return "\(scheme)://\(host)"
    }

    /// Capture groups (index 0 = whole match) of the first regex match, or nil.
    static func match(_ pattern: String, in text: String, options: NSRegularExpression.Options = []) -> [String]? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: options),
              let m = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) else { return nil }
        return (0..<m.numberOfRanges).map { i in
            Range(m.range(at: i), in: text).map { String(text[$0]) } ?? ""
        }
    }
}
