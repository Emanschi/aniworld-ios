import Foundation
import AniworldKit

/// How a finished download is stored on disk.
enum DownloadKind: String, Codable {
    /// `.movpkg` bundle created by `AVAssetDownloadURLSession` (HLS).
    case hls
    /// Plain file (mp4) written by a URLSession download task.
    case file
}

/// A finished, playable offline episode.
struct DownloadRecord: Codable, Identifiable, Hashable {
    /// Episode id (`EpisodeRef.id`).
    var id: String
    var series: SeriesSummary
    var episode: EpisodeRef
    var language: StreamLanguage?
    var hoster: String
    /// Path relative to the app's home directory (the container path changes between installs/updates).
    var relativePath: String
    var kind: DownloadKind
    var sizeBytes: Int64
    var createdAt: Date
}

enum DownloadJobStatus: String, Codable {
    case queued
    /// Resolving the stream or transferring data.
    case active
    case failed
}

/// A pending / running / failed download. Finished ones become a `DownloadRecord`.
struct DownloadJob: Codable, Identifiable, Hashable {
    var id: String
    var series: SeriesSummary
    var episode: EpisodeRef
    var language: StreamLanguage?
    var status: DownloadJobStatus
    var progress: Double
    var currentHoster: String?
    /// Hosters that already failed for this job (used for fallback via `excluding:`).
    var triedHosters: [String]
    var errorMessage: String?
    var addedAt: Date
}

/// What the UI shows for one episode.
enum DownloadState: Equatable {
    case none
    case queued
    case downloading(Double)
    case downloaded
    case failed(String)
}

/// Contents of `index.json`.
struct DownloadIndex: Codable {
    var records: [DownloadRecord] = []
    var jobs: [DownloadJob] = []
}

enum DownloadFormat {
    static func bytes(_ value: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: value, countStyle: .file)
    }
}
