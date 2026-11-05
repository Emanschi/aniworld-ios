import Foundation

/// Pure, side-effect-free merge of several library states (last-writer-wins by timestamp).
///
/// Properties (checked by hand and by a Linux script during development):
/// - commutative and idempotent: the result does not depend on the order of `states`, and
///   merging a merged result with any of its inputs yields the same result;
/// - favorites: union of adds, an add survives only if `addedAt` is newer than its tombstone;
/// - history: per slug the newest `updatedAt` wins unless a tombstone / `historyClearedAt` is newer;
/// - progress: per episode id newer `updatedAt` wins (equal time: watched wins, then larger position);
/// - languages: per slug newest wins;
/// - custom skip times: per key the newest `updatedAt` wins unless a tombstone is newer;
/// - `resetAt`: the newest reset wins and everything stamped at or before it is dropped.
///
/// Scenarios:
/// 1. iPhone removes X at t=10, iPad (stale) still has X addedAt=1 → tombstone 10 > 1 → X gone.
/// 2. iPad re-adds X at t=20 → addedAt 20 > tombstone 10 → X back everywhere.
/// 3. iPhone clears history at t=30; iPad watched Y at t=25 (not yet synced) → Y dropped;
///    iPad watches Z at t=40 → Z survives.
/// 4. iPhone resets at t=50 → every entry with timestamp <= 50 on any device is dropped.
enum LibraryMerge {
    static let tombstoneLifetime: TimeInterval = 90 * 24 * 3600
    static let historyLimit = 50

    static func merge(_ states: [LibraryState], now: Date = Date()) -> LibraryState {
        var out = LibraryState()
        out.resetAt = states.compactMap { $0.resetAt }.max()
        out.historyClearedAt = states.compactMap { $0.historyClearedAt }.max()
        let reset = out.resetAt ?? .distantPast
        let cleared = max(out.historyClearedAt ?? .distantPast, reset)
        let tombstoneCutoff = max(now.addingTimeInterval(-tombstoneLifetime), reset)

        // Favorites
        let favTombs = maxDates(states.map { $0.favoriteTombstones })
        var bestFav: [String: FavoriteEntry] = [:]
        for state in states {
            for fav in state.favorites where fav.addedAt > reset {
                if let current = bestFav[fav.id] {
                    if isBetter(fav, than: current) { bestFav[fav.id] = fav }
                } else {
                    bestFav[fav.id] = fav
                }
            }
        }
        out.favorites = bestFav.values
            .filter { $0.addedAt > (favTombs[$0.id] ?? .distantPast) }
            .sorted { a, b in a.addedAt != b.addedAt ? a.addedAt > b.addedAt : a.id < b.id }
        out.favoriteTombstones = favTombs.filter { $0.value > tombstoneCutoff }

        // History
        let histTombs = maxDates(states.map { $0.historyTombstones })
        var bestHist: [String: WatchEntry] = [:]
        for state in states {
            for entry in state.history where entry.updatedAt > cleared {
                if let current = bestHist[entry.id] {
                    if isBetter(entry, than: current) { bestHist[entry.id] = entry }
                } else {
                    bestHist[entry.id] = entry
                }
            }
        }
        let liveHistory = bestHist.values
            .filter { $0.updatedAt > (histTombs[$0.id] ?? .distantPast) }
            .sorted { a, b in a.updatedAt != b.updatedAt ? a.updatedAt > b.updatedAt : a.id < b.id }
        out.history = Array(liveHistory.prefix(historyLimit))
        out.historyTombstones = histTombs.filter { $0.value > max(tombstoneCutoff, cleared) }

        // Progress
        for state in states {
            for (id, p) in state.progress where p.updatedAt > reset {
                if let current = out.progress[id] {
                    if isBetter(p, than: current) { out.progress[id] = p }
                } else {
                    out.progress[id] = p
                }
            }
        }

        // Languages
        for state in states {
            for (slug, choice) in state.languages where out.resetAt == nil || choice.updatedAt > reset {
                if let current = out.languages[slug] {
                    if choice.updatedAt > current.updatedAt
                        || (choice.updatedAt == current.updatedAt && choice.language.rawValue > current.language.rawValue) {
                        out.languages[slug] = choice
                    }
                } else {
                    out.languages[slug] = choice
                }
            }
        }

        // Custom skip times (own intro/outro): newest entry per key wins, tombstones delete.
        let skipTombs = maxDates(states.map { $0.customSkipTombstones })
        var bestSkip: [String: CustomSkip] = [:]
        for state in states {
            for skip in state.customSkips where skip.updatedAt > reset {
                if let current = bestSkip[skip.key] {
                    if isBetter(skip, than: current) { bestSkip[skip.key] = skip }
                } else {
                    bestSkip[skip.key] = skip
                }
            }
        }
        out.customSkips = bestSkip.values
            .filter { $0.updatedAt > (skipTombs[$0.key] ?? .distantPast) }
            .sorted { $0.key < $1.key }
        out.customSkipTombstones = skipTombs.filter { $0.value > tombstoneCutoff }
        return out
    }

    // MARK: Helpers

    private static func isBetter(_ a: CustomSkip, than b: CustomSkip) -> Bool {
        if a.updatedAt != b.updatedAt { return a.updatedAt > b.updatedAt }
        // Deterministic tie-break so the merge stays commutative.
        let ta: [Double] = [a.introStart ?? -1, a.introEnd ?? -1, a.outroStart ?? -1, a.outroEnd ?? -1]
        let tb: [Double] = [b.introStart ?? -1, b.introEnd ?? -1, b.outroStart ?? -1, b.outroEnd ?? -1]
        for (x, y) in zip(ta, tb) where x != y { return x > y }
        return false
    }

    private static func maxDates(_ maps: [[String: Date]]) -> [String: Date] {
        var result: [String: Date] = [:]
        for map in maps {
            for (key, date) in map where date > (result[key] ?? .distantPast) { result[key] = date }
        }
        return result
    }

    private static func isBetter(_ a: FavoriteEntry, than b: FavoriteEntry) -> Bool {
        if a.addedAt != b.addedAt { return a.addedAt > b.addedAt }
        return a.series.title > b.series.title
    }

    private static func isBetter(_ a: WatchEntry, than b: WatchEntry) -> Bool {
        if a.updatedAt != b.updatedAt { return a.updatedAt > b.updatedAt }
        if a.position != b.position { return a.position > b.position }
        return a.episode.id > b.episode.id
    }

    private static func isBetter(_ a: EpisodeProgress, than b: EpisodeProgress) -> Bool {
        if a.updatedAt != b.updatedAt { return a.updatedAt > b.updatedAt }
        if a.watched != b.watched { return a.watched }
        if a.position != b.position { return a.position > b.position }
        return a.duration > b.duration
    }
}
