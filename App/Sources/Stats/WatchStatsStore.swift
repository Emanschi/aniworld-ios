import Foundation
import Observation
import UIKit
import AniworldKit

/// Local store of watch sessions for the statistics ("Dein Monatsrückblick").
/// Persisted as JSON in Application Support (`stats.json`), keeps the last 24 months and is
/// merged across devices by `LibrarySyncService` (see `StatsMerge`).
@MainActor
@Observable
final class WatchStatsStore {
    /// All known sessions (this device and, after a sync, the other devices), oldest first.
    private(set) var sessions: [WatchSession] = []
    /// slug → genres / age rating (filled whenever a series page is loaded).
    private(set) var seriesMeta: [String: SeriesMeta] = [:]
    private(set) var resetAt: Date?
    /// Download data volume per device and day (own entries and, after a sync, the other devices').
    private(set) var dataUsage: [DataUsageEntry] = []
    /// Set when this device kept its own statistics against a newer reset ("Dieses Gerät behalten").
    @ObservationIgnored private(set) var restoredAt: Date?

    /// Increases with every change made on this device (the sync layer uses it to decide on writing).
    @ObservationIgnored private(set) var localRevision = 0
    /// Called after every local change; not for changes applied by `apply(merged:)`.
    @ObservationIgnored var onChange: (() -> Void)?

    @ObservationIgnored let deviceID: String
    @ObservationIgnored private let fileURL: URL?
    @ObservationIgnored private var lastUsageNotify: Date?
    @ObservationIgnored private var saveTask: Task<Void, Never>?
    @ObservationIgnored private var lifecycleTokens: [NSObjectProtocol] = []

    /// Same key as `LibrarySyncService`, so both always agree on this device's id.
    private static let deviceIDKey = "sync.deviceID"

    private struct Snapshot: Codable {
        var sessions: [WatchSession] = []
        var seriesMeta: [String: SeriesMeta] = [:]
        var resetAt: Date?
        var dataUsage: [DataUsageEntry] = []
        var restoredAt: Date?

        init() {}

        enum CodingKeys: String, CodingKey { case sessions, seriesMeta, resetAt, dataUsage, restoredAt }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            sessions = try c.decodeIfPresent([WatchSession].self, forKey: .sessions) ?? []
            seriesMeta = try c.decodeIfPresent([String: SeriesMeta].self, forKey: .seriesMeta) ?? [:]
            resetAt = try c.decodeIfPresent(Date.self, forKey: .resetAt)
            dataUsage = try c.decodeIfPresent([DataUsageEntry].self, forKey: .dataUsage) ?? []
            restoredAt = try c.decodeIfPresent(Date.self, forKey: .restoredAt)
        }
    }

    /// - Parameters:
    ///   - fileURL: override for tests/previews (nil = nothing is written); default is Application Support/stats.json.
    ///   - initialSessions: sample data for previews, used instead of the file.
    init(fileURL: URL? = WatchStatsStore.defaultFileURL(), initialSessions: [WatchSession]? = nil,
         initialMeta: [String: SeriesMeta] = [:]) {
        self.fileURL = fileURL
        let defaults = UserDefaults.standard
        if let id = defaults.string(forKey: Self.deviceIDKey) {
            deviceID = id
        } else {
            let id = UUID().uuidString
            defaults.set(id, forKey: Self.deviceIDKey)
            deviceID = id
        }
        if let initialSessions {
            sessions = initialSessions
            seriesMeta = initialMeta
        } else {
            load()
        }
        let center = NotificationCenter.default
        let names: [Notification.Name] = [
            UIApplication.willResignActiveNotification,
            UIApplication.didEnterBackgroundNotification,
            UIApplication.willTerminateNotification,
        ]
        for name in names {
            let token = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.flush() }
            }
            lifecycleTokens.append(token)
        }
    }

    // MARK: Persistence

    nonisolated static func defaultFileURL() -> URL? {
        guard let base = try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                                      appropriateFor: nil, create: true) else { return nil }
        return base.appendingPathComponent("stats.json")
    }

    private func load() {
        guard let fileURL, let data = try? Data(contentsOf: fileURL),
              let snap = try? JSONDecoder().decode(Snapshot.self, from: data) else { return }
        let merged = StatsMerge.merge([StatsState(sessions: snap.sessions, seriesMeta: snap.seriesMeta,
                                                  resetAt: snap.resetAt, dataUsage: snap.dataUsage,
                                                  restoredAt: snap.restoredAt)])
        sessions = merged.sessions
        seriesMeta = merged.seriesMeta
        resetAt = merged.resetAt
        dataUsage = merged.dataUsage
        restoredAt = snap.restoredAt
    }

    private func scheduleSave(notify: Bool) {
        if notify {
            localRevision += 1
            onChange?()
        }
        NotificationCenter.default.post(name: .watchStatsDidChange, object: nil)
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            guard !Task.isCancelled else { return }
            self?.flush()
        }
    }

    /// Writes to disk immediately (also called when the app goes to the background).
    func flush() {
        saveTask?.cancel()
        saveTask = nil
        guard let fileURL else { return }
        var snap = Snapshot()
        snap.sessions = sessions
        snap.seriesMeta = seriesMeta
        snap.resetAt = resetAt
        snap.dataUsage = dataUsage
        snap.restoredAt = restoredAt
        guard let data = try? JSONEncoder().encode(snap) else { return }
        try? data.write(to: fileURL, options: [.atomic])
    }

    // MARK: Recording

    /// Stores a finished session. Sessions under 30 seconds of watch time are ignored.
    func record(_ session: WatchSession) {
        guard session.watchedSeconds >= 30 else { return }
        var s = session
        s.deviceID = deviceID
        sessions.removeAll { $0.id == s.id }
        sessions.append(s)
        pruneOld()
        scheduleSave(notify: true)
        flush()
    }

    /// Adds downloaded bytes to today's entry of this device. Called often while a download runs, so it
    /// only saves with the usual delay and tells the sync layer at most once a minute.
    func addDownloadBytes(_ bytes: Int64, cellular: Bool, now: Date = Date(), calendar: Calendar = .current) {
        guard bytes > 0 else { return }
        let day: Date = calendar.startOfDay(for: now)
        let id = "\(deviceID)-dl-\(Int(day.timeIntervalSince1970))"
        var entry: DataUsageEntry
        if let index = dataUsage.firstIndex(where: { $0.id == id }) {
            entry = dataUsage[index]
        } else {
            entry = DataUsageEntry(id: id, day: day, deviceID: deviceID, updatedAt: now)
        }
        if cellular { entry.cellularBytes += bytes } else { entry.wifiBytes += bytes }
        entry.updatedAt = now
        if let index = dataUsage.firstIndex(where: { $0.id == id }) {
            dataUsage[index] = entry
        } else {
            dataUsage.append(entry)
        }
        let notify = lastUsageNotify.map { now.timeIntervalSince($0) > 60 } ?? true
        if notify { lastUsageNotify = now }
        scheduleSave(notify: notify)
    }

    /// Remembers genres / age rating of a series (called whenever a series page was loaded).
    func noteSeries(_ detail: SeriesDetail) {
        let slug = detail.summary.slug
        guard !detail.genres.isEmpty || detail.ageRating != nil else { return }
        if let current = seriesMeta[slug], current.genres == detail.genres, current.ageRating == detail.ageRating {
            return
        }
        seriesMeta[slug] = SeriesMeta(genres: detail.genres, ageRating: detail.ageRating, updatedAt: Date())
        scheduleSave(notify: true)
    }

    func hasMeta(forSlug slug: String) -> Bool { seriesMeta[slug] != nil }

    /// "Statistik zurücksetzen": wipes everything here and, through sync, on all devices.
    func reset() {
        sessions = []
        seriesMeta = [:]
        dataUsage = []
        resetAt = Date()
        scheduleSave(notify: true)
        flush()
    }

    private func pruneOld() {
        let cutoff = Date().addingTimeInterval(-StatsMerge.retention)
        sessions.removeAll { $0.endedAt <= cutoff }
        dataUsage.removeAll { $0.updatedAt <= cutoff }
    }

    // MARK: Convenience for the UI

    var firstSessionDate: Date? { WatchStatsCalculator.firstDate(of: sessions) }

    func stats(for period: StatsPeriod, calendar: Calendar = .current) -> WatchStats {
        WatchStatsCalculator(
            sessions: sessions,
            interval: period.interval(calendar: calendar),
            calendar: calendar,
            seriesMeta: seriesMeta,
            previousInterval: period.previousInterval(calendar: calendar),
            dataUsage: dataUsage
        ).compute()
    }

    /// Daily streak over all data (a day counts with at least one completely watched episode).
    func streak(now: Date = Date(), calendar: Calendar = .current) -> WatchStreak {
        WatchStreak.compute(sessions: sessions, now: now, calendar: calendar)
    }

    // MARK: Sync support

    /// Everything known locally (the sync layer merges it with the other devices' data).
    func exportState() -> StatsState {
        StatsState(sessions: sessions, seriesMeta: seriesMeta, resetAt: resetAt, dataUsage: dataUsage,
                   restoredAt: restoredAt)
    }

    /// What this device writes into its own sync file: only sessions that were recorded here.
    func exportOwnState() -> StatsState {
        StatsState(sessions: sessions.filter { $0.deviceID == deviceID }, seriesMeta: seriesMeta, resetAt: resetAt,
                   dataUsage: dataUsage.filter { $0.deviceID == deviceID }, restoredAt: restoredAt)
    }

    /// Replaces the local data with a merged state. Does not trigger `onChange`.
    func apply(merged: StatsState) {
        // `restoredAt` belongs to this device only; whatever the merge reports is not adopted.
        var merged = merged
        merged.restoredAt = restoredAt
        guard merged != exportState() else { return }
        sessions = merged.sessions
        seriesMeta = merged.seriesMeta
        resetAt = merged.resetAt
        dataUsage = merged.dataUsage
        scheduleSave(notify: false)
    }

    /// "Dieses Gerät behalten" / backup restore: keeps (or restores) the given statistics and marks
    /// them as newer than any reset known on the other devices, so that a remote reset cannot drop them.
    /// - Parameter floor: newest `resetAt` seen elsewhere.
    func assertLocal(restoring state: StatsState? = nil, floor: Date?) {
        if let state {
            sessions = state.sessions
            seriesMeta = state.seriesMeta
            resetAt = state.resetAt
            dataUsage = state.dataUsage
        }
        let newest = [Date(), floor, resetAt].compactMap { $0 }.max() ?? Date()
        restoredAt = newest.addingTimeInterval(1)
        scheduleSave(notify: true)
        flush()
    }
}
