import Foundation

/// A stream URL plus the headers the CDN expects.
struct ExtractedStream: Equatable, Sendable {
    var url: URL
    var headers: [String: String]
}

/// Resolves a hoster's `/redirect/<id>` URL to a playable stream. Returns nil on any failure
/// so the resolver can fall through to the next hoster.
protocol StreamExtractor: Sendable {
    func extract(redirectURL: URL, http: HTTPFetching) async -> ExtractedStream?
}

/// Extractors keyed by lowercase hoster name. Register a new hoster by adding an entry.
struct ExtractorRegistry: Sendable {
    var extractors: [String: StreamExtractor]

    static let `default` = ExtractorRegistry(extractors: [
        "voe": VOEExtractor(),
        "vidmoly": VidmolyExtractor(),
    ])

    func extractor(for hosterName: String) -> StreamExtractor? {
        extractors[hosterName.trimmingCharacters(in: .whitespaces).lowercased()]
    }
}
