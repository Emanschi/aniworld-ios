import Foundation
import Observation
import AniworldKit

/// User settings, persisted in UserDefaults. Owned by Agent C.
@MainActor
@Observable
final class SettingsStore {
    var languagePriority: [StreamLanguage] = StreamPreferences.default.languagePriority
    var hosterPriority: [String] = StreamPreferences.default.hosterPriority
    /// Play the next episode automatically when one ends.
    var autoplayNext: Bool = true
    /// Countdown before autoplay, seconds.
    var autoplayCountdown: Int = 8
    /// Length of the "Intro überspringen" jump, seconds.
    var introSkipSeconds: Int = 85
    /// Check that a stream's segments load before playing (slower, more reliable).
    var verifyStreams: Bool = true

    var streamPreferences: StreamPreferences {
        StreamPreferences(languagePriority: languagePriority, hosterPriority: hosterPriority)
    }

    init() {
        // TODO(Agent C): load from UserDefaults and persist on change
    }
}
