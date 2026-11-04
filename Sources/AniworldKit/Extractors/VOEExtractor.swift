import Foundation

/// VOE: `/redirect/<id>` 301s to `voe.sx/e/<code>`, a JS stub that bounces to a rotating mirror
/// (`window.location.href = '...'`). The mirror embeds the stream in a
/// `<script type="application/json">["..."]</script>` blob obfuscated as
///
///     rot13 -> strip junk pairs -> base64 -> shift each char by -3 -> reverse -> base64 -> JSON
///
/// The JSON exposes `source` (HLS master, preferred) and `direct_access_url` (progressive).
struct VOEExtractor: StreamExtractor {
    static let junkPairs = ["@$", "^^", "~@", "%?", "*~", "!!", "#&"]
    static let maxBounces = 3

    static func parseEmbed(_ html: String) -> URL? {
        guard let m = Support.match(#"<script[^>]+type="application/json"[^>]*>(.*?)</script>"#, in: html,
                                    options: [.dotMatchesLineSeparators]),
              let obj = decodeBlob(m[1].trimmingCharacters(in: .whitespacesAndNewlines)) else { return nil }
        for key in ["source", "direct_access_url"] {
            if let s = obj[key] as? String, !s.isEmpty, let url = URL(string: s) { return url }
        }
        return nil
    }

    /// Applies the reversible obfuscation pipeline to the JSON-array blob.
    static func decodeBlob(_ blob: String) -> [String: Any]? {
        guard let data = blob.data(using: .utf8),
              let outer = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) else { return nil }
        guard var s = (outer as? [Any])?.first as? String ?? outer as? String else { return nil }
        s = rot13(s)
        for pair in junkPairs { s = s.replacingOccurrences(of: pair, with: "") }
        guard let first = lenientBase64(s), let firstText = String(data: first, encoding: .utf8) else { return nil }
        let shifted = String(String.UnicodeScalarView(firstText.unicodeScalars.reversed().compactMap { scalar in
            Unicode.Scalar(scalar.value &- 3)
        }))
        guard let second = lenientBase64(shifted),
              let obj = try? JSONSerialization.jsonObject(with: second) as? [String: Any] else { return nil }
        return obj
    }

    static func rot13(_ s: String) -> String {
        String(String.UnicodeScalarView(s.unicodeScalars.map { c in
            switch c.value {
            case 65...90: return Unicode.Scalar((c.value - 65 + 13) % 26 + 65)!
            case 97...122: return Unicode.Scalar((c.value - 97 + 13) % 26 + 97)!
            default: return c
            }
        }))
    }

    /// Like Python's `b64decode`: ignores characters outside the alphabet, tolerates missing padding.
    static func lenientBase64(_ s: String) -> Data? {
        let alphabet = Set("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/")
        var cleaned = String(s.filter { alphabet.contains($0) })
        guard !cleaned.isEmpty else { return nil }
        while cleaned.count % 4 != 0 { cleaned += "=" }
        return Data(base64Encoded: cleaned)
    }

    func extract(redirectURL: URL, http: HTTPFetching) async -> ExtractedStream? {
        guard var response = try? await http.get(redirectURL), response.status < 400 else { return nil }
        // Follow the JS bounce to the mirror domain.
        for _ in 0..<Self.maxBounces {
            guard let hop = Support.match(#"window\.location\.href\s*=\s*['"]([^'"]+)['"]"#, in: response.text),
                  let next = Support.absoluteURL(hop[1], base: response.url),
                  let nextResponse = try? await http.get(next, headers: ["Referer": Support.origin(of: response.url)]),
                  nextResponse.status < 400 else { break }
            response = nextResponse
        }
        guard let url = Self.parseEmbed(response.text) else { return nil }
        return ExtractedStream(url: url, headers: [
            "Referer": Support.origin(of: response.url),
            "User-Agent": AniworldClient.userAgent,
        ])
    }
}
