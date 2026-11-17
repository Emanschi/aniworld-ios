import Foundation
import AniworldKit
import Observation
import UIKit

/// Keeps the local library in sync with other devices through a user-picked iCloud Drive folder
/// (`<picked>/.aniworld-sync/devices/<deviceID>.json`, one file per device).
/// File IO runs in detached tasks; merging and applying happens on the main actor.
@MainActor
@Observable
final class LibrarySyncService {
    // MARK: Observable state (for Settings / onboarding)

    private(set) var isConfigured: Bool
    private(set) var isSyncing = false
    private(set) var lastSyncAt: Date?
    private(set) var lastError: String?
    private(set) var devices: [SyncDevice] = []
    /// Drives the first-launch onboarding sheet.
    var showOnboarding = false
    /// Set when merging would remove or replace local data; the app asks the user (nothing is applied
    /// and nothing is written until `resolveConflict` is called).
    var conflict: SyncConflictInfo?
    /// Date of the newest local backup (nil = none), for the settings section.
    private(set) var lastBackupAt: Date?

    // MARK: Internals

    private enum Mode { case full, writeOnly }

    @ObservationIgnored private let library: LibraryStore
    @ObservationIgnored private let stats: WatchStatsStore
    @ObservationIgnored private let defaults = UserDefaults.standard
    @ObservationIgnored private var started = false
    @ObservationIgnored private var tokens: [NSObjectProtocol] = []
    @ObservationIgnored private var debounceTask: Task<Void, Never>?
    @ObservationIgnored private var pendingSince: Date?
    @ObservationIgnored private var retryTask: Task<Void, Never>?
    @ObservationIgnored private var retryCount = 0
    @ObservationIgnored private var queuedMode: Mode?
    @ObservationIgnored private var lastWrittenState: LibraryState?
    @ObservationIgnored private var lastWriteAt: Date?
    @ObservationIgnored private var lastWrittenStatsRevision: Int?
    @ObservationIgnored private var lastRemoteSnapshots: [SyncSnapshot] = []
    @ObservationIgnored private let backups = LibraryBackupStore.standard()

    private static let deviceIDKey = "sync.deviceID"
    private static let dismissedKey = "sync.onboardingDismissed"
    private static let lastSyncKey = "sync.lastSyncAt"
    private static let debounceSeconds: TimeInterval = 5
    private static let maxDebounceSeconds: TimeInterval = 60
    private static let heartbeatSeconds: TimeInterval = 3600

    let deviceID: String

    init(library: LibraryStore, stats: WatchStatsStore) {
        self.library = library
        self.stats = stats
        let defaults = UserDefaults.standard
        if let id = defaults.string(forKey: Self.deviceIDKey) {
            deviceID = id
        } else {
            let id = UUID().uuidString
            defaults.set(id, forKey: Self.deviceIDKey)
            deviceID = id
        }
        isConfigured = FolderBookmark.isStored
        if let t = defaults.object(forKey: Self.lastSyncKey) as? Date { lastSyncAt = t }
        lastBackupAt = backups?.latest()?.createdAt
    }

    var deviceName: String { UIDevice.current.name }

    // MARK: Lifecycle

    /// Idempotent. Call once the UI is up.
    func start() {
        guard !started else { return }
        started = true

        library.onChange = { [weak self] in self?.libraryDidChange() }
        stats.onChange = { [weak self] in self?.libraryDidChange() }

        let center = NotificationCenter.default
        tokens.append(center.addObserver(forName: UIApplication.didBecomeActiveNotification,
                                         object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.requestSync(.full, background: false) }
        })
        let resign: [Notification.Name] = [
            UIApplication.willResignActiveNotification,
            UIApplication.didEnterBackgroundNotification,
        ]
        for name in resign {
            tokens.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.requestSync(.writeOnly, background: true) }
            })
        }

        showOnboarding = !isConfigured && !defaults.bool(forKey: Self.dismissedKey)
        requestSync(.full, background: false)
    }

    // MARK: Setup

    /// Called with the folder the user picked.
    func configure(pickedFolder url: URL) {
        do {
            try FolderBookmark.save(url)
        } catch {
            lastError = "Ordner konnte nicht gespeichert werden: \(error.localizedDescription)"
            return
        }
        isConfigured = true
        showOnboarding = false
        conflict = nil
        lastRemoteSnapshots = []
        lastError = nil
        lastWrittenState = nil
        lastWrittenStatsRevision = nil
        devices = []
        requestSync(.full, background: false, force: true)
    }

    func skipOnboarding() {
        defaults.set(true, forKey: Self.dismissedKey)
        showOnboarding = false
    }

    /// Removes the bookmark; local data is kept.
    func disable() {
        FolderBookmark.clear()
        isConfigured = false
        devices = []
        conflict = nil
        lastRemoteSnapshots = []
        lastError = nil
        lastSyncAt = nil
        defaults.removeObject(forKey: Self.lastSyncKey)
        lastWrittenState = nil
        lastWrittenStatsRevision = nil
        debounceTask?.cancel()
        retryTask?.cancel()
        // Don't show the onboarding again right after switching sync off.
        defaults.set(true, forKey: Self.dismissedKey)
    }

    func syncNow() {
        requestSync(.full, background: false, force: true)
    }

    // MARK: Conflict decision & backups

    /// The user's answer from the "Gespeicherte Stände unterscheiden sich" sheet.
    func resolveConflict(_ choice: SyncConflictChoice) {
        guard let info = conflict else { return }
        conflict = nil
        let now = Date()
        let local = library.exportState()
        let localStats = stats.exportState()
        let remoteStates: [LibraryState] = info.remoteSnapshots.map { $0.state }
        let remoteStats: [StatsState] = info.remoteSnapshots.map { $0.statsState }
        // Whatever happens next may remove local data: keep a copy first.
        let reason: String
        switch choice {
        case .merge: reason = "Vor dem Zusammenführen"
        case .adoptRemote: reason = "Vor dem Übernehmen von iCloud"
        case .keepLocal: reason = "Vor dem Behalten dieses Geräts"
        }
        writeBackup(reason: reason, library: local, stats: localStats)

        switch choice {
        case .merge:
            library.apply(merged: LibraryMerge.merge([local] + remoteStates, now: now))
            stats.apply(merged: StatsMerge.merge([localStats] + remoteStats, now: now))
        case .adoptRemote:
            let adopted = SyncPlanner.adoptRemote(remote: info.remoteSnapshots, localStats: localStats, now: now)
            library.apply(merged: adopted.library)
            stats.apply(merged: adopted.stats)
        case .keepLocal:
            library.apply(merged: SyncPlanner.assertLocal(local, over: remoteStates, now: now))
            stats.assertLocal(floor: remoteStats.compactMap { $0.resetAt }.max())
        }
        library.flush()
        requestSync(.full, background: false, force: true)
    }

    /// Puts the newest backup back and makes this device authoritative again (so the next sync
    /// doesn't undo it). Returns false if there is no readable backup.
    @discardableResult
    func restoreLastBackup() -> Bool {
        guard let backup = backups?.latest() else { return false }
        conflict = nil
        // The current state is saved first, so the restore itself can be undone.
        writeBackup(reason: "Vor dem Wiederherstellen", library: library.exportState(), stats: stats.exportState())
        let remoteStates: [LibraryState] = lastRemoteSnapshots.map { $0.state }
        library.apply(merged: SyncPlanner.assertLocal(backup.library, over: remoteStates))
        stats.assertLocal(restoring: backup.stats,
                          floor: lastRemoteSnapshots.compactMap { $0.statsResetAt }.max())
        library.flush()
        requestSync(.full, background: false, force: true)
        return true
    }

    private func writeBackup(reason: String, library: LibraryState, stats: StatsState) {
        guard let backups else { return }
        let backup = LibraryBackup(createdAt: Date(), reason: reason, library: library, stats: stats)
        if (try? backups.write(backup)) != nil { lastBackupAt = backup.createdAt }
    }

    // MARK: Triggers

    private func libraryDidChange() {
        guard isConfigured else { return }
        let now = Date()
        if pendingSince == nil { pendingSince = now }
        let waited = now.timeIntervalSince(pendingSince ?? now)
        let delay = max(0, min(Self.debounceSeconds, Self.maxDebounceSeconds - waited))
        debounceTask?.cancel()
        debounceTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard !Task.isCancelled else { return }
            self?.pendingSince = nil
            self?.requestSync(.writeOnly, background: false)
        }
    }

    private func requestSync(_ mode: Mode, background: Bool, force: Bool = false) {
        guard isConfigured else { return }
        if isSyncing {
            // Run again afterwards; a full sync supersedes a write-only one.
            if queuedMode != .full { queuedMode = mode }
            return
        }
        Task { [weak self] in
            await self?.run(mode, background: background, force: force)
        }
    }

    // MARK: Sync run

    private final class BackgroundTaskBox: @unchecked Sendable {
        var id = UIBackgroundTaskIdentifier.invalid
    }

    private func run(_ mode: Mode, background: Bool, force: Bool) async {
        guard isConfigured, !isSyncing else { return }
        guard let picked = FolderBookmark.resolve() else {
            lastError = SyncError.folderUnavailable.localizedDescription
            return
        }
        isSyncing = true

        let box = BackgroundTaskBox()
        if background {
            box.id = UIApplication.shared.beginBackgroundTask(withName: "LibrarySync") {
                MainActor.assumeIsolated {
                    if box.id != .invalid {
                        UIApplication.shared.endBackgroundTask(box.id)
                        box.id = .invalid
                    }
                }
            }
        }
        defer {
            if box.id != .invalid {
                UIApplication.shared.endBackgroundTask(box.id)
                box.id = .invalid
            }
        }

        let ownID = deviceID
        var pending = 0
        do {
            if mode == .full {
                let read = try await Task.detached(priority: .utility) {
                    try SyncFolderIO.readRemote(picked: picked, ownDeviceID: ownID)
                }.value
                lastRemoteSnapshots = read.snapshots
                // Compare against the *current* local state (it may have changed during the read).
                // Nothing is applied if the merge would remove or replace local data: the user decides.
                let plan = SyncPlanner.plan(local: library.exportState(), localStats: stats.exportState(),
                                            localDeviceName: deviceName, remote: read.snapshots)
                if plan.needsDecision {
                    var info = SyncConflictInfo(local: plan.local, remote: plan.remote, losses: plan.losses,
                                                remoteSnapshots: read.snapshots)
                    if let existing = conflict { info.id = existing.id }
                    conflict = info
                } else {
                    conflict = nil
                    library.apply(merged: plan.merged)
                    stats.apply(merged: plan.mergedStats)
                }
                devices = read.snapshots
                    .map { SyncDevice(id: $0.deviceID, name: $0.deviceName, writtenAt: $0.writtenAt) }
                    .sorted { $0.writtenAt > $1.writtenAt }
                pending = read.pendingDownloads
            }

            // While the user has not decided, this device's file stays as it is.
            let state = library.exportState()
            let stale = lastWriteAt.map { Date().timeIntervalSince($0) > Self.heartbeatSeconds } ?? true
            let statsRevision = stats.localRevision
            if conflict == nil,
               force || stale || state != lastWrittenState || statsRevision != lastWrittenStatsRevision {
                let snapshot = SyncSnapshot(deviceID: ownID, deviceName: deviceName, state: state,
                                            stats: stats.exportOwnState())
                try await Task.detached(priority: .utility) {
                    try SyncFolderIO.write(snapshot, picked: picked)
                }.value
                lastWrittenState = state
                lastWrittenStatsRevision = statsRevision
                lastWriteAt = Date()
            }
            lastError = nil
            if mode == .full, conflict == nil {
                let now = Date()
                lastSyncAt = now
                defaults.set(now, forKey: Self.lastSyncKey)
            }
        } catch {
            lastError = error.localizedDescription
            if let syncError = error as? SyncError, case .folderDownloading = syncError { pending += 1 }
        }
        isSyncing = false

        if pending > 0, retryCount < 4 {
            retryCount += 1
            retryTask?.cancel()
            retryTask = Task { [weak self] in
                try? await Task.sleep(nanoseconds: 15_000_000_000)
                guard !Task.isCancelled else { return }
                self?.requestSync(.full, background: false)
            }
        } else if pending == 0 {
            retryCount = 0
        }

        if let next = queuedMode {
            queuedMode = nil
            await run(next, background: background, force: false)
        }
    }
}
