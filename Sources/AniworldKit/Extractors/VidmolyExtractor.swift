import Foundation

/// Vidmoly: `/redirect/<id>` lands on an embed page whose inline jwplayer setup has
/// `sources: [{ file: 'https://.../master.m3u8?...' }]`.
struct VidmolyExtractor: StreamExtractor {
    static func parseEmbed(_ html: String) -> URL? {
        guard let m = Support.match(#"sources\s*:\s*\[\s*\{\s*file\s*:\s*["']([^"']+)["']"#, in: html) else { return nil }
        return URL(string: m[1])
    }

    func extract(redirectURL: URL, http: HTTPFetching) async -> ExtractedStream? {
        guard let response = try? await http.get(redirectURL, headers: ["Referer": AniworldClient.defaultBaseURL.absoluteString]),
              response.status < 400, let url = Self.parseEmbed(response.text) else { return nil }
        return ExtractedStream(url: url, headers: [
            "Referer": Support.origin(of: response.url) + "/",
            "User-Agent": AniworldClient.userAgent,
        ])
    }
}
