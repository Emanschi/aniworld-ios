import AVFoundation
import Foundation

/// Upper limit for the streaming quality (adaptive HLS streams only). Not to be confused with
/// `DownloadQuality`, which is the compression of finished downloads.
enum StreamQuality: String, Codable, CaseIterable, Identifiable, Sendable {
    case auto
    case high
    case medium
    case low

    var id: String { rawValue }

    var title: String {
        switch self {
        case .auto: return "Automatisch"
        case .high: return "Hoch (1080p)"
        case .medium: return "Mittel (720p)"
        case .low: return "Datensparend (480p)"
        }
    }

    /// `AVPlayerItem.preferredPeakBitRate` in bit/s; 0 = no limit.
    var peakBitRate: Double {
        switch self {
        case .auto: return 0
        case .high: return 5_000_000
        case .medium: return 2_500_000
        case .low: return 1_200_000
        }
    }

    /// `AVPlayerItem.preferredMaximumResolution`; `.zero` = no limit.
    var maxResolution: CGSize {
        switch self {
        case .auto: return .zero
        case .high: return CGSize(width: 1920, height: 1080)
        case .medium: return CGSize(width: 1280, height: 720)
        case .low: return CGSize(width: 854, height: 480)
        }
    }

    /// Bit rate used for data estimates. "Automatisch" assumes a typical full-HD stream.
    var estimatedBitRate: Double {
        self == .auto ? 6_000_000 : peakBitRate
    }

    var gigabytesPerHour: Double { estimatedBitRate * 3600 / 8 / 1_000_000_000 }

    /// e.g. "ca. 0,5 GB/Std." ("bis ca." for the unlimited option).
    var dataPerHourText: String {
        let value = StreamDataFormat.gigabytes(gigabytesPerHour)
        return self == .auto ? "bis ca. \(value) GB/Std." : "ca. \(value) GB/Std."
    }

    func estimatedBytes(seconds: Double) -> Double {
        estimatedBitRate * max(seconds, 0) / 8
    }

    /// Applies the limit to a (possibly already playing) item. Only has an effect on adaptive (HLS) streams.
    func apply(to item: AVPlayerItem) {
        item.preferredPeakBitRate = peakBitRate
        item.preferredMaximumResolution = maxResolution
    }
}

enum StreamDataFormat {
    /// German decimal formatting with one fraction digit, e.g. "1,1".
    static func gigabytes(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "de_DE")
        formatter.minimumFractionDigits = 1
        formatter.maximumFractionDigits = 1
        return formatter.string(from: NSNumber(value: value)) ?? String(format: "%.1f", value)
    }

    /// "ca. 450 MB" / "ca. 1,2 GB" for a byte count.
    static func approx(bytes: Double) -> String {
        if bytes >= 1_000_000_000 {
            return "ca. \(gigabytes(bytes / 1_000_000_000)) GB"
        }
        let mb = max(Int((bytes / 10_000_000).rounded()) * 10, 10)
        return "ca. \(mb) MB"
    }

    /// Rough size of downloaded episodes (source quality, about 0,3-0,6 GB each).
    static func downloadEstimate(episodes count: Int) -> String {
        if count <= 1 { return "ca. 300–600 MB" }
        return "ca. \(gigabytes(Double(count) * 0.3))–\(gigabytes(Double(count) * 0.6)) GB"
    }
}
