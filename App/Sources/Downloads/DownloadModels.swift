import Foundation
import AniworldKit

/// How a finished download is stored on disk.
enum DownloadKind: String, Codable {
    /// `.movpkg` bundle created by `AVAssetDownloadURLSession` (HLS).
    case hls
    /// Plain file (mp4) written by a URLSession download task.
    case file
}

/// Quality preset for offline downloads and video compression.
enum DownloadQuality: String, Codable, CaseIterable, Identifiable, Sendable {
    case high = "1080p"
    case medium = "720p"
    case low = "480p"

    var id: String { rawValue }
    var title: String {
        switch self {
        case .high: return "Hoch (HEVC, Originalauflösung)"
        case .medium: return "Ausgewogen (720p, H.264)"
        case .low: return "Kompakt (480p, H.264)"
        }
    }
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
    /// Ob die Datei nach dem Download neu kodiert (komprimiert) wurde.
    var isCompressed: Bool? = false
    /// Kurzbezeichnung des Ergebnisses ("HEVC", "720p", "480p"), nil wenn nicht komprimiert.
    var compressionLabel: String? = nil
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
    /// True while the finished file is being re-encoded (status stays `.active`, no record yet).
    var isCompressing: Bool? = nil
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
