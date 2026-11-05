import Foundation
import AniworldKit

/// Turns the player's ticks into `WatchSession`s.
///
/// - The watch time counts real (wall-clock) seconds in which the video was really playing;
///   seeks and scrubbing do not add time.
/// - A session opens on the first tick of actual playback and ends on episode switch, player close,
///   app background, a hoster/language reload, or after a pause of more than 10 minutes.
/// - Sessions under 30 seconds are dropped by the store.
@MainActor
final class WatchSessionRecorder {
    /// Everything that describes the episode being played.
    struct Context {
        var series: SeriesSummary
        var episode: EpisodeRef
        var language: StreamLanguage?
        var hoster: String
        var offline: Bool
    }

    private struct Open {
        var id = UUID().uuidString
        var startedAt: Date
        var lastPlayingAt: Date
        var watchedSeconds: Double = 0
        var rateSeconds: Double = 0
        var skippedSeconds: Double = 0
    }

    static let maxPauseSeconds: TimeInterval = 10 * 60
    private static let maxTickGap: TimeInterval = 2.0
    private static let completedFraction = 0.9

    private let store: WatchStatsStore
    private var context: Context?
    private var open: Open?
    private var lastTickAt: Date?
    private var duration: Double = 0
    /// Highest watched fraction of the current episode (survives session splits).
    private var maxFraction: Double = 0
    private var endedNaturally = false

    init(store: WatchStatsStore) {
        self.store = store
    }

    /// A new item was attached. Ends any running session first.
    func prepare(_ context: Context) {
        let sameEpisode = self.context?.episode.id == context.episode.id
        finish()
        if !sameEpisode {
            maxFraction = 0
            endedNaturally = false
        }
        self.context = context
        lastTickAt = nil
        duration = 0
    }

    /// Playback of the episode is over (leaving it): ends the session and forgets the episode.
    func clear() {
        finish()
        context = nil
        maxFraction = 0
        endedNaturally = false
    }

    func updateContext(language: StreamLanguage?, hoster: String?) {
        guard var c = context else { return }
        if let language { c.language = language }
        if let hoster { c.hoster = hoster }
        context = c
    }

    /// Called on every periodic time-observer tick.
    func tick(now: Date = Date(), position: Double, duration: Double, isPlaying: Bool, rate: Double) {
        guard context != nil else { return }
        if duration > 0 {
            self.duration = duration
            maxFraction = max(maxFraction, min(max(position / duration, 0), 1))
        }
        let delta: Double = lastTickAt.map { now.timeIntervalSince($0) } ?? 0
        lastTickAt = now
        guard isPlaying else { return }

        if let o = open, now.timeIntervalSince(o.lastPlayingAt) > Self.maxPauseSeconds {
            // Long pause: close at the last moment of real playback, continue in a new session.
            finish(endedAt: o.lastPlayingAt)
        }
        if open == nil {
            open = Open(startedAt: now, lastPlayingAt: now)
        }
        // Gaps (pause, buffering, backgrounding) are not watch time.
        if delta > 0, delta <= Self.maxTickGap, var o = open {
            o.watchedSeconds += delta
            o.rateSeconds += delta * max(rate, 0)
            o.lastPlayingAt = now
            open = o
        } else if var o = open {
            o.lastPlayingAt = now
            open = o
        }
    }

    /// Media seconds skipped by an intro / outro / recap skip.
    func noteSkipped(seconds: Double) {
        guard seconds > 0, seconds < 3600, var o = open else { return }
        o.skippedSeconds += seconds
        open = o
    }

    /// The item played to its end.
    func markEnded() {
        endedNaturally = true
        maxFraction = 1
    }

    /// Ends the running session (if any) and stores it.
    func finish(endedAt: Date? = nil) {
        defer {
            open = nil
            lastTickAt = nil
        }
        guard let o = open, let c = context else { return }
        guard o.watchedSeconds >= 30 else { return }
        let end: Date = endedAt ?? o.lastPlayingAt
        let avgRate: Double = o.watchedSeconds > 0 ? o.rateSeconds / o.watchedSeconds : 1
        let session = WatchSession(
            id: o.id,
            seriesSlug: c.series.slug,
            seriesTitle: c.series.title,
            coverURL: c.series.coverURL,
            season: c.episode.season,
            episode: c.episode.number,
            language: c.language,
            hoster: c.hoster,
            startedAt: o.startedAt,
            endedAt: max(end, o.startedAt),
            watchedSeconds: o.watchedSeconds,
            playbackRate: avgRate,
            episodeDuration: duration,
            completed: endedNaturally || maxFraction >= Self.completedFraction,
            skippedSeconds: o.skippedSeconds,
            wasOffline: c.offline,
            deviceID: store.deviceID
        )
        store.record(session)
    }
}
