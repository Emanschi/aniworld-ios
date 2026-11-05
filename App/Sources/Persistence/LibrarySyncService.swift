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
                // Merge against the *current* local state (it may have changed during the read).
                let merged = LibraryMerge.merge([library.exportState()] + read.snapshots.map { $0.state })
                library.apply(merged: merged)
                let mergedStats = StatsMerge.merge([stats.exportState()] + read.snapshots.map { $0.statsState })
                stats.apply(merged: mergedStats)
                devices = read.snapshots
                    .map { SyncDevice(id: $0.deviceID, name: $0.deviceName, writtenAt: $0.writtenAt) }
                    .sorted { $0.writtenAt > $1.writtenAt }
                pending = read.pendingDownloads
            }

            let state = library.exportState()
            let stale = lastWriteAt.map { Date().timeIntervalSince($0) > Self.heartbeatSeconds } ?? true
            let statsRevision = stats.localRevision
            if force || stale || state != lastWrittenState || statsRevision != lastWrittenStatsRevision {
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
            if mode == .full {
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
