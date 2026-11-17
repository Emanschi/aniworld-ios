import Foundation
import AniworldKit

// Pure logic (Foundation + AniworldKit only, no UIKit) behind the "Gespeicherte Stände unterscheiden
// sich" decision. Compiled into the app and, via the `AniworldSyncLogic` SwiftPM target, tested on Linux.

/// What the user can choose when local and iCloud state differ.
enum SyncConflictChoice: Sendable {
    /// This device is authoritative; other devices adopt its state.
    case keepLocal
    /// Local data is replaced by what the other devices have.
    case adoptRemote
    /// Normal last-writer-wins merge (default).
    case merge
}

/// Short description of one side, shown in the conflict sheet.
struct SyncStateSummary: Equatable, Sendable {
    var favorites: Int
    var history: Int
    /// Episodes with a position or marked watched.
    var episodesWithProgress: Int
    var customSkips: Int
    var statsSessions: Int
    var lastChanged: Date?
    var deviceName: String?

    init(favorites: Int = 0, history: Int = 0, episodesWithProgress: Int = 0, customSkips: Int = 0,
         statsSessions: Int = 0, lastChanged: Date? = nil, deviceName: String? = nil) {
        self.favorites = favorites
        self.history = history
        self.episodesWithProgress = episodesWithProgress
        self.customSkips = customSkips
        self.statsSessions = statsSessions
        self.lastChanged = lastChanged
        self.deviceName = deviceName
    }

    init(state: LibraryState, stats: StatsState, deviceName: String?, lastChanged: Date? = nil) {
        self.init(favorites: state.favorites.count,
                  history: state.history.count,
                  episodesWithProgress: state.progress.values.filter { $0.watched || $0.position > 0 }.count,
                  customSkips: state.customSkips.count,
                  statsSessions: stats.sessions.count,
                  lastChanged: lastChanged ?? state.latestChange,
                  deviceName: deviceName)
    }
}

extension LibraryState {
    /// Newest timestamp of any entry or removal marker (approximation of "last changed").
    var latestChange: Date? {
        var dates: [Date] = []
        dates.append(contentsOf: favorites.map { $0.addedAt })
        dates.append(contentsOf: history.map { $0.updatedAt })
        dates.append(contentsOf: progress.values.map { $0.updatedAt })
        dates.append(contentsOf: customSkips.map { $0.updatedAt })
        dates.append(contentsOf: languages.values.map { $0.updatedAt })
        dates.append(contentsOf: favoriteTombstones.values)
        dates.append(contentsOf: historyTombstones.values)
        dates.append(contentsOf: customSkipTombstones.values)
        if let resetAt { dates.append(resetAt) }
        if let historyClearedAt { dates.append(historyClearedAt) }
        return dates.filter { $0 > Date.distantPast }.max()
    }
}

/// Local data that a merge would remove or turn back.
struct SyncLosses: Equatable, Sendable {
    var favorites = 0
    var history = 0
    /// Progress records that would disappear.
    var progressRemoved = 0
    /// Progress records that would go back (watched → unwatched, or clearly earlier position).
    var progressBackwards = 0
    var customSkips = 0
    var statsSessions = 0

    var isEmpty: Bool { total == 0 }
    var total: Int { favorites + history + progressRemoved + progressBackwards + customSkips + statsSessions }
}

struct SyncPlan: Sendable {
    var merged: LibraryState
    var mergedStats: StatsState
    var losses: SyncLosses
    var local: SyncStateSummary
    var remote: SyncStateSummary
    /// A merge would remove or replace local data: don't apply silently.
    var needsDecision: Bool { !losses.isEmpty }
}

/// What the sync service keeps while the conflict sheet is open.
struct SyncConflictInfo: Identifiable, Sendable {
    var id = UUID()
    var local: SyncStateSummary
    var remote: SyncStateSummary
    var losses: SyncLosses
    var remoteSnapshots: [SyncSnapshot]
}

enum SyncPlanner {
    /// A position that moved back by less than this is treated as normal (re-watching a bit).
    static let backwardsTolerance: Double = 60

    /// Computes the merge WITHOUT applying it and describes what it would change locally.
    static func plan(local: LibraryState, localStats: StatsState, localDeviceName: String,
                     remote: [SyncSnapshot], now: Date = Date()) -> SyncPlan {
        let remoteStates: [LibraryState] = remote.map { $0.state }
        let remoteStats: [StatsState] = remote.map { $0.statsState }
        let merged = LibraryMerge.merge([local] + remoteStates, now: now)
        let mergedStats = StatsMerge.merge([localStats] + remoteStats, now: now)
        let losses = self.losses(local: local, merged: merged, localStats: localStats,
                                 mergedStats: mergedStats)

        let remoteOnly = LibraryMerge.merge(remoteStates, now: now)
        let remoteOnlyStats = StatsMerge.merge(remoteStats, now: now)
        let newest = remote.max { $0.writtenAt < $1.writtenAt }
        let newestName: String? = newest.map { $0.deviceName.isEmpty ? "Unbekanntes Gerät" : $0.deviceName }
        var remoteSummary = SyncStateSummary(state: remoteOnly, stats: remoteOnlyStats, deviceName: newestName)
        remoteSummary.lastChanged = newest?.writtenAt ?? remoteOnly.latestChange
        let localSummary = SyncStateSummary(state: local, stats: localStats, deviceName: localDeviceName)
        return SyncPlan(merged: merged, mergedStats: mergedStats, losses: losses,
                        local: localSummary, remote: remoteSummary)
    }

    /// Local data that is present in `local` but missing / turned back in `merged`.
    static func losses(local: LibraryState, merged: LibraryState,
                       localStats: StatsState, mergedStats: StatsState) -> SyncLosses {
        var out = SyncLosses()
        let mergedFavorites = Set(merged.favorites.map { $0.id })
        out.favorites = local.favorites.filter { !mergedFavorites.contains($0.id) }.count
        let mergedHistory = Set(merged.history.map { $0.id })
        out.history = local.history.filter { !mergedHistory.contains($0.id) }.count

        for (id, p) in local.progress where p.watched || p.position > 0 {
            guard let m = merged.progress[id] else {
                out.progressRemoved += 1
                continue
            }
            if (p.watched && !m.watched) || (!m.watched && m.position + backwardsTolerance < p.position) {
                out.progressBackwards += 1
            }
        }

        let mergedSkips = Set(merged.customSkips.map { $0.key })
        out.customSkips = local.customSkips.filter { !mergedSkips.contains($0.key) }.count

        let mergedSessions = Set(mergedStats.sessions.map { $0.id })
        out.statsSessions = localStats.sessions.filter { !mergedSessions.contains($0.id) }.count
        return out
    }

    /// "iCloud übernehmen": the state of the other devices alone.
    static func adoptRemote(remote: [SyncSnapshot], localStats: StatsState,
                            now: Date = Date()) -> (library: LibraryState, stats: StatsState) {
        let library = LibraryMerge.merge(remote.map { $0.state }, now: now)
        // Statistics are recorded per device, so this device's own sessions are only replaced when a
        // remote statistics reset says so (same as a normal merge).
        let stats = StatsMerge.merge([localStats] + remote.map { $0.statsState }, now: now)
        return (library, stats)
    }

    /// Newest reset / clear / removal marker of the given states (the point in time the local state
    /// has to be newer than so that none of them can delete local items).
    static func newestMarker(of states: [LibraryState]) -> Date {
        var newest = Date.distantPast
        for s in states {
            var dates: [Date] = [s.resetAt, s.historyClearedAt].compactMap { $0 }
            dates.append(contentsOf: s.favoriteTombstones.values)
            dates.append(contentsOf: s.historyTombstones.values)
            dates.append(contentsOf: s.customSkipTombstones.values)
            for d in dates where d > newest { newest = d }
        }
        return newest
    }

    /// "Dieses Gerät behalten": returns `local` as the authoritative state. Older app versions only
    /// know last-writer-wins plus `resetAt`, so the authority is expressed in those terms: a new
    /// `resetAt` that is newer than every reset / clear / tombstone found elsewhere, and every local
    /// entry re-stamped to just after it (the relative order of favorites and history is kept).
    /// Other devices then drop everything older and adopt this state.
    static func assertLocal(_ local: LibraryState, over remote: [LibraryState],
                            now: Date = Date()) -> LibraryState {
        let marker = max(newestMarker(of: remote), local.resetAt ?? Date.distantPast)
        let resetAt = max(now, marker.addingTimeInterval(0.5))
        let base = resetAt.addingTimeInterval(1)

        func rankMap(_ dates: [Date]) -> [Date: Date] {
            let sorted = Array(Set(dates)).sorted()
            var map: [Date: Date] = [:]
            for (i, d) in sorted.enumerated() { map[d] = base.addingTimeInterval(Double(i) * 0.001) }
            return map
        }

        var out = LibraryState()
        out.resetAt = resetAt

        let favRanks = rankMap(local.favorites.map { $0.addedAt })
        out.favorites = local.favorites.map { fav in
            var f = fav
            f.addedAt = favRanks[fav.addedAt] ?? base
            return f
        }
        let histRanks = rankMap(local.history.map { $0.updatedAt })
        out.history = local.history.map { entry in
            var e = entry
            e.updatedAt = histRanks[entry.updatedAt] ?? base
            return e
        }
        out.progress = local.progress.mapValues { p in
            var q = p
            q.updatedAt = base
            return q
        }
        out.languages = local.languages.mapValues { c in
            var d = c
            d.updatedAt = base
            return d
        }
        out.customSkips = local.customSkips.map { skip in
            var s = skip
            s.updatedAt = base
            return s
        }
        return out
    }
}
