import Foundation
import Observation
import AniworldKit

/// User settings, persisted in UserDefaults. Owned by Agent C.
@MainActor
@Observable
final class SettingsStore {
    var languagePriority: [StreamLanguage] = StreamPreferences.default.languagePriority {
        didSet {
            let normalized = Self.normalize(languagePriority)
            if normalized != languagePriority { languagePriority = normalized; return }
            defaults.set(languagePriority.map(\.rawValue), forKey: Keys.languagePriority)
        }
    }
    var hosterPriority: [String] = StreamPreferences.default.hosterPriority {
        didSet { defaults.set(hosterPriority, forKey: Keys.hosterPriority) }
    }
    /// Play the next episode automatically when one ends.
    var autoplayNext: Bool = true {
        didSet { defaults.set(autoplayNext, forKey: Keys.autoplayNext) }
    }
    /// Countdown before autoplay, seconds.
    var autoplayCountdown: Int = 8 {
        didSet { defaults.set(autoplayCountdown, forKey: Keys.autoplayCountdown) }
    }
    /// Length of the "Intro überspringen" jump, seconds.
    var introSkipSeconds: Int = 85 {
        didSet { defaults.set(introSkipSeconds, forKey: Keys.introSkipSeconds) }
    }
    /// Automatic detection of intro/outro timestamps.
    var enableSkipDetection: Bool = true {
        didSet { defaults.set(enableSkipDetection, forKey: Keys.enableSkipDetection) }
    }
    /// Automatically skip opening when timestamps are detected.
    var autoSkipIntro: Bool = false {
        didSet { defaults.set(autoSkipIntro, forKey: Keys.autoSkipIntro) }
    }
    /// Automatically skip ending when timestamps are detected.
    var autoSkipEnding: Bool = false {
        didSet { defaults.set(autoSkipEnding, forKey: Keys.autoSkipEnding) }
    }
    /// With autoplay on: when the outro starts, skip it and start the next episode (via the countdown).
    var autoNextOnOutro: Bool = false {
        didSet { defaults.set(autoNextOnOutro, forKey: Keys.autoNextOnOutro) }
    }
    /// Check that a stream's segments load before playing (slower, more reliable).
    var verifyStreams: Bool = true {
        didSet { defaults.set(verifyStreams, forKey: Keys.verifyStreams) }
    }
    /// Lokale Mitteilung bei neuen Folgen der Favoriten.
    var notifyNewEpisodes: Bool = false {
        didSet { defaults.set(notifyNewEpisodes, forKey: Keys.notifyNewEpisodes) }
    }
    /// Mitteilung bei neuer App-Version.
    var notifyAppUpdates: Bool = true {
        didSet { defaults.set(notifyAppUpdates, forKey: Keys.notifyAppUpdates) }
    }
    /// Automatische Komprimierung heruntergeladener Folgen (HEVC / Hardware-Transcoding).
    var compressDownloads: Bool = true {
        didSet { defaults.set(compressDownloads, forKey: Keys.compressDownloads) }
    }
    /// Zielauflösung / Kompressionsstufe für Downloads.
    var downloadQuality: DownloadQuality = .medium {
        didSet { defaults.set(downloadQuality.rawValue, forKey: Keys.downloadQuality) }
    }
    /// Gesehene Folgen nach dem Anschauen automatisch aus den Downloads löschen.
    var autoDeleteWatchedDownloads: Bool = false {
        didSet { defaults.set(autoDeleteWatchedDownloads, forKey: Keys.autoDeleteWatchedDownloads) }
    }

    var streamPreferences: StreamPreferences {
        StreamPreferences(languagePriority: languagePriority, hosterPriority: hosterPriority)
    }

    @ObservationIgnored private let defaults: UserDefaults

    private enum Keys {
        static let languagePriority = "settings.languagePriority"
        static let hosterPriority = "settings.hosterPriority"
        static let autoplayNext = "settings.autoplayNext"
        static let autoplayCountdown = "settings.autoplayCountdown"
        static let introSkipSeconds = "settings.introSkipSeconds"
        static let enableSkipDetection = "settings.enableSkipDetection"
        static let autoSkipIntro = "settings.autoSkipIntro"
        static let autoSkipEnding = "settings.autoSkipEnding"
        static let autoNextOnOutro = "settings.autoNextOnOutro"
        static let verifyStreams = "settings.verifyStreams"
        static let notifyNewEpisodes = "settings.notifyNewEpisodes"
        static let notifyAppUpdates = "settings.notifyAppUpdates"
        static let compressDownloads = "settings.compressDownloads"
        static let downloadQuality = "settings.downloadQuality"
        static let autoDeleteWatchedDownloads = "settings.autoDeleteWatchedDownloads"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        // Assigning inside init does not trigger didSet.
        if let raw = defaults.array(forKey: Keys.languagePriority) as? [String] {
            languagePriority = Self.normalize(raw.compactMap { StreamLanguage(rawValue: $0) })
        }
        if let hosters = defaults.array(forKey: Keys.hosterPriority) as? [String], !hosters.isEmpty {
            hosterPriority = hosters
        }
        if defaults.object(forKey: Keys.autoplayNext) != nil {
            autoplayNext = defaults.bool(forKey: Keys.autoplayNext)
        }
        if defaults.object(forKey: Keys.autoplayCountdown) != nil {
            autoplayCountdown = max(defaults.integer(forKey: Keys.autoplayCountdown), 1)
        }
        if defaults.object(forKey: Keys.introSkipSeconds) != nil {
            introSkipSeconds = max(defaults.integer(forKey: Keys.introSkipSeconds), 1)
        }
        if defaults.object(forKey: Keys.enableSkipDetection) != nil {
            enableSkipDetection = defaults.bool(forKey: Keys.enableSkipDetection)
        }
        if defaults.object(forKey: Keys.autoSkipIntro) != nil {
            autoSkipIntro = defaults.bool(forKey: Keys.autoSkipIntro)
        }
        if defaults.object(forKey: Keys.autoSkipEnding) != nil {
            autoSkipEnding = defaults.bool(forKey: Keys.autoSkipEnding)
        }
        if defaults.object(forKey: Keys.autoNextOnOutro) != nil {
            autoNextOnOutro = defaults.bool(forKey: Keys.autoNextOnOutro)
        }
        if defaults.object(forKey: Keys.verifyStreams) != nil {
            verifyStreams = defaults.bool(forKey: Keys.verifyStreams)
        }
        if defaults.object(forKey: Keys.notifyNewEpisodes) != nil {
            notifyNewEpisodes = defaults.bool(forKey: Keys.notifyNewEpisodes)
        }
        if defaults.object(forKey: Keys.notifyAppUpdates) != nil {
            notifyAppUpdates = defaults.bool(forKey: Keys.notifyAppUpdates)
        }
        if defaults.object(forKey: Keys.compressDownloads) != nil {
            compressDownloads = defaults.bool(forKey: Keys.compressDownloads)
        }
        if let rawQuality = defaults.string(forKey: Keys.downloadQuality),
           let quality = DownloadQuality(rawValue: rawQuality) {
            downloadQuality = quality
        }
        if defaults.object(forKey: Keys.autoDeleteWatchedDownloads) != nil {
            autoDeleteWatchedDownloads = defaults.bool(forKey: Keys.autoDeleteWatchedDownloads)
        }
    }

    /// Removes duplicates and appends missing languages so all three are always present.
    private static func normalize(_ list: [StreamLanguage]) -> [StreamLanguage] {
        var seen = Set<StreamLanguage>()
        var result = list.filter { seen.insert($0).inserted }
        for lang in StreamLanguage.allCases where !seen.contains(lang) {
            result.append(lang)
        }
        return result
    }
}
