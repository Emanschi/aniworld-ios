import AVFoundation
import Foundation
import Network
import Observation
import UIKit
import AniworldKit

// MARK: - Paths

/// File locations. Everything lives under Application Support and is excluded from backups / iCloud.
/// Paths are stored relative to the home directory because the container path changes between installs.
enum DownloadPaths {
    /// `Application Support/Downloads` (created on demand, excluded from backup).
    static var directory: URL {
        let fm = FileManager.default
        let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        var dir = base.appendingPathComponent("Downloads", isDirectory: true)
        if !fm.fileExists(atPath: dir.path) {
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? dir.setResourceValues(values)
        return dir
    }

    static var indexURL: URL { directory.appendingPathComponent("index.json") }

    static func excludeFromBackup(_ url: URL) {
        var copy = url
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? copy.setResourceValues(values)
    }

    static func relativePath(for url: URL) -> String {
        let home = URL(fileURLWithPath: NSHomeDirectory()).resolvingSymlinksInPath().path
        let path = url.resolvingSymlinksInPath().path
        if path.hasPrefix(home + "/") {
            return String(path.dropFirst(home.count + 1))
        }
        return path
    }

    static func absoluteURL(_ relative: String) -> URL {
        if relative.hasPrefix("/") { return URL(fileURLWithPath: relative) }
        return URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(relative)
    }

    static func safeName(_ id: String) -> String {
        let allowed = Set("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_")
        return String(id.map { allowed.contains($0) ? $0 : "_" })
    }

    /// Size of a file or directory tree in bytes.
    static func diskSize(of url: URL) -> Int64 {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: url.path, isDirectory: &isDir) else { return 0 }
        if !isDir.boolValue {
            let attrs = try? fm.attributesOfItem(atPath: url.path)
            return (attrs?[.size] as? NSNumber)?.int64Value ?? 0
        }
        let keys: [URLResourceKey] = [.totalFileAllocatedSizeKey, .fileSizeKey, .isRegularFileKey]
        guard let enumerator = fm.enumerator(at: url, includingPropertiesForKeys: keys) else { return 0 }
        var total: Int64 = 0
        while let next = enumerator.nextObject() {
            guard let fileURL = next as? URL else { continue }
            let values = try? fileURL.resourceValues(forKeys: Set(keys))
            if values?.isRegularFile == true {
                total += Int64(values?.totalFileAllocatedSize ?? values?.fileSize ?? 0)
            }
        }
        return total
    }
}

// MARK: - Network Watcher

@MainActor
final class DownloadNetworkWatcher {
    static let shared = DownloadNetworkWatcher()
    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "DownloadNetworkWatcher")
    private(set) var isConnectedToWiFi = true
    var onPathChange: (() -> Void)?

    init() {
        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in
                let onWiFi = path.usesInterfaceType(.wifi)
                let changed = self?.isConnectedToWiFi != onWiFi
                self?.isConnectedToWiFi = onWiFi
                if changed {
                    self?.onPathChange?()
                }
            }
        }
        monitor.start(queue: queue)
    }
}

// MARK: - Background session plumbing

/// Completion handlers handed over by `application(_:handleEventsForBackgroundURLSession:)`.
enum DownloadBackgroundEvents {
    @MainActor static var handlers: [String: () -> Void] = [:]
}

/// Receives all session callbacks (on the main queue) and forwards them to the manager.
final class DownloadSessionDelegate: NSObject, AVAssetDownloadDelegate, URLSessionDownloadDelegate {
    weak var manager: DownloadManager?

    // HLS progress
    func urlSession(_ session: URLSession, assetDownloadTask: AVAssetDownloadTask, didLoad timeRange: CMTimeRange,
                    totalTimeRangesLoaded loadedTimeRanges: [NSValue], timeRangeExpectedToLoad: CMTimeRange) {
        guard let id = assetDownloadTask.taskDescription else { return }
        var loaded: Double = 0
        for value in loadedTimeRanges {
            loaded += value.timeRangeValue.duration.seconds
        }
        let expected = timeRangeExpectedToLoad.duration.seconds
        let fraction: Double = expected > 0 ? min(1, loaded / expected) : 0
        let m = manager
        Task { @MainActor in m?.updateProgress(id: id, fraction: fraction) }
    }

    // HLS finished
    func urlSession(_ session: URLSession, assetDownloadTask: AVAssetDownloadTask, didFinishDownloadingTo location: URL) {
        guard let id = assetDownloadTask.taskDescription else { return }
        DownloadPaths.excludeFromBackup(location)
        let m = manager
        Task { @MainActor in m?.finished(id: id, location: location, kind: .hls) }
    }

    // File progress
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64,
                    totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        guard let id = downloadTask.taskDescription, totalBytesExpectedToWrite > 0 else { return }
        let fraction = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
        let m = manager
        Task { @MainActor in m?.updateProgress(id: id, fraction: fraction) }
    }

    // File finished: the temporary file is deleted when this returns, so move it synchronously.
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        guard let id = downloadTask.taskDescription else { return }
        let fm = FileManager.default
        let destination = DownloadPaths.directory.appendingPathComponent(DownloadPaths.safeName(id) + ".mp4")
        let m = manager
        do {
            if fm.fileExists(atPath: destination.path) { try fm.removeItem(at: destination) }
            try fm.moveItem(at: location, to: destination)
            DownloadPaths.excludeFromBackup(destination)
            Task { @MainActor in m?.finished(id: id, location: destination, kind: .file) }
        } catch {
            let message = error.localizedDescription
            Task { @MainActor in m?.failed(id: id, message: message) }
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let error, let id = task.taskDescription else { return }
        if (error as NSError).code == NSURLErrorCancelled { return }
        let message = error.localizedDescription
        let m = manager
        Task { @MainActor in m?.failed(id: id, message: message) }
    }

    func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        let identifier = session.configuration.identifier ?? ""
        Task { @MainActor in
            let handler = DownloadBackgroundEvents.handlers.removeValue(forKey: identifier)
            handler?()
        }
    }
}

/// Needed so iOS can hand over background-session events after the app was relaunched.
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, handleEventsForBackgroundURLSession identifier: String,
                     completionHandler: @escaping () -> Void) {
        Task { @MainActor in
            DownloadBackgroundEvents.handlers[identifier] = completionHandler
        }
    }
}

// MARK: - Manager

/// Offline downloads: queue (max. 2 parallel), HLS via `AVAssetDownloadURLSession`, mp4 via a
/// background `URLSession`. State is kept in a local JSON index (never synced).
@MainActor
@Observable
final class DownloadManager {
    static let maxConcurrent = 2
    static let maxHosterAttempts = 3
    private static let hlsSessionID = "com.aniworldios.app.downloads.hls"
    private static let fileSessionID = "com.aniworldios.app.downloads.file"

    private(set) var records: [DownloadRecord] = []
    private(set) var jobs: [String: DownloadJob] = [:]

    @ObservationIgnored private let service: AniworldService
    @ObservationIgnored private let settings: SettingsStore
    @ObservationIgnored private let sessionDelegate = DownloadSessionDelegate()
    @ObservationIgnored private var hlsSession: AVAssetDownloadURLSession?
    @ObservationIgnored private var fileSession: URLSession?
    @ObservationIgnored private var resolveTasks: [String: Task<Void, Never>] = [:]
    @ObservationIgnored private var restored = false

    init(service: AniworldService, settings: SettingsStore) {
        self.service = service
        self.settings = settings
        loadIndex()
        sessionDelegate.manager = self

        let hlsConfig = URLSessionConfiguration.background(withIdentifier: Self.hlsSessionID)
        hlsConfig.sessionSendsLaunchEvents = true
        hlsConfig.isDiscretionary = false
        hlsConfig.allowsCellularAccess = !settings.downloadOnlyOnWiFi
        hlsSession = AVAssetDownloadURLSession(
            configuration: hlsConfig, assetDownloadDelegate: sessionDelegate, delegateQueue: OperationQueue.main)

        let fileConfig = URLSessionConfiguration.background(withIdentifier: Self.fileSessionID)
        fileConfig.sessionSendsLaunchEvents = true
        fileConfig.isDiscretionary = false
        fileConfig.allowsCellularAccess = !settings.downloadOnlyOnWiFi
        fileSession = URLSession(configuration: fileConfig, delegate: sessionDelegate, delegateQueue: OperationQueue.main)

        DownloadNetworkWatcher.shared.onPathChange = { [weak self] in
            self?.networkChanged()
        }

        Task { await self.restoreTasks() }
    }

    // MARK: Queries

    var isWaitingForWiFi: Bool {
        settings.downloadOnlyOnWiFi && !DownloadNetworkWatcher.shared.isConnectedToWiFi
    }

    var totalBytes: Int64 { records.reduce(Int64(0)) { $0 + $1.sizeBytes } }

    var activeJobs: [DownloadJob] {
        jobs.values.sorted { $0.addedAt < $1.addedAt }
    }

    func state(for episodeID: String) -> DownloadState {
        if records.contains(where: { $0.id == episodeID }) { return .downloaded }
        guard let job = jobs[episodeID] else { return .none }
        switch job.status {
        case .queued: return .queued
        case .active: return .downloading(job.progress)
        case .failed: return .failed(job.errorMessage ?? "Download fehlgeschlagen")
        }
    }

    func localURL(for episode: EpisodeRef) -> URL? {
        guard let record = records.first(where: { $0.id == episode.id }) else { return nil }
        let url = DownloadPaths.absoluteURL(record.relativePath)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    /// A stream pointing at the local file, or nil when the episode is not downloaded.
    func localStream(for episode: EpisodeRef) -> ResolvedStream? {
        guard let url = localURL(for: episode),
              let record = records.first(where: { $0.id == episode.id }) else { return nil }
        return ResolvedStream(url: url, headers: [:], hoster: "Offline", language: record.language)
    }

    // MARK: Commands

    func download(series: SeriesSummary, episodes: [EpisodeRef], language: StreamLanguage?) {
        let base = Date()
        var index = 0
        for episode in episodes {
            switch state(for: episode.id) {
            case .none, .failed:
                let job = DownloadJob(
                    id: episode.id, series: series, episode: episode, language: language,
                    status: .queued, progress: 0, currentHoster: nil, triedHosters: [],
                    errorMessage: nil, addedAt: base.addingTimeInterval(Double(index) * 0.001))
                jobs[episode.id] = job
                index += 1
            default:
                break
            }
        }
        saveIndex()
        pump()
    }

    func retry(_ id: String) {
        guard var job = jobs[id], job.status == .failed else { return }
        job.status = .queued
        job.progress = 0
        job.triedHosters = []
        job.errorMessage = nil
        jobs[id] = job
        saveIndex()
        pump()
    }

    /// Cancels a queued / running / failed download.
    func cancel(_ id: String) {
        resolveTasks[id]?.cancel()
        resolveTasks[id] = nil
        jobs[id] = nil
        cancelSessionTasks(id: id)
        saveIndex()
        pump()
    }

    /// Deletes a finished download from disk.
    func delete(_ id: String) {
        if jobs[id] != nil { cancel(id) }
        guard let record = records.first(where: { $0.id == id }) else { return }
        try? FileManager.default.removeItem(at: DownloadPaths.absoluteURL(record.relativePath))
        records.removeAll { $0.id == id }
        saveIndex()
    }

    func deleteAll(seriesSlug: String) {
        let ids = records.filter { $0.series.slug == seriesSlug }.map { $0.id }
        for id in ids { delete(id) }
    }

    /// Deletes all downloads of a specific season.
    func deleteSeason(seriesSlug: String, season: Int) {
        let ids = records.filter { $0.series.slug == seriesSlug && $0.episode.season == season }.map { $0.id }
        for id in ids { delete(id) }
    }

    /// Deletes all downloaded episodes across all series.
    func deleteAll() {
        for record in records { delete(record.id) }
    }

    func hasDownloads(seriesSlug: String) -> Bool {
        records.contains { $0.series.slug == seriesSlug }
    }

    func hasDownloads(in episodes: [EpisodeRef]) -> Bool {
        let ids = Set(episodes.map(\.id))
        return records.contains { ids.contains($0.id) }
    }

    // MARK: Queue

    private func networkChanged() {
        if !isWaitingForWiFi {
            pump()
        }
    }

    private func pump() {
        guard restored else { return }
        if isWaitingForWiFi { return }
        var running = jobs.values.filter { $0.status == .active }.count
        let queued = jobs.values.filter { $0.status == .queued }.sorted { $0.addedAt < $1.addedAt }
        for job in queued {
            if running >= Self.maxConcurrent { break }
            start(job.id)
            running += 1
        }
    }

    private func start(_ id: String) {
        guard var job = jobs[id] else { return }
        job.status = .active
        job.progress = 0
        job.errorMessage = nil
        jobs[id] = job
        saveIndex()
        resolveTasks[id] = Task { [weak self] in
            await self?.resolveAndStart(id)
        }
    }

    private func resolveAndStart(_ id: String) async {
        guard let job = jobs[id] else { return }
        do {
            let hosters = try await service.hosters(for: job.episode)
            guard !hosters.isEmpty else { throw AniworldError.noPlayableStream }
            let prefs = settings.streamPreferences
            let languages = service.availableLanguages(hosters, preferences: prefs)
            var chosen: StreamLanguage?
            if let wanted = job.language, languages.contains(wanted) {
                chosen = wanted
            } else {
                chosen = languages.first
            }
            let stream = try await service.resolveStream(
                hosters: hosters, language: chosen, preferences: prefs,
                verify: settings.verifyStreams, excluding: Set(job.triedHosters))
            try Task.checkCancellation()
            guard jobs[id]?.status == .active else { return }
            begin(stream: stream, language: stream.language ?? chosen, id: id)
        } catch {
            if Task.isCancelled || error is CancellationError { return }
            if let a = error as? AniworldError, a == .cancelled { return }
            markFailed(id: id, message: Self.message(for: error))
        }
    }

    private func begin(stream: ResolvedStream, language: StreamLanguage?, id: String) {
        guard var job = jobs[id] else { return }
        job.currentHoster = stream.hoster
        job.language = language
        jobs[id] = job
        saveIndex()

        let title = "\(job.series.title) – \(job.episode.code)"
        let ext = stream.url.pathExtension.lowercased()
        if ext == "mp4" || ext == "m4v" {
            var request = URLRequest(url: stream.url)
            for (key, value) in stream.headers {
                request.setValue(value, forHTTPHeaderField: key)
            }
            guard let session = fileSession else {
                markFailed(id: id, message: "Download-Sitzung nicht verfügbar")
                return
            }
            let task = session.downloadTask(with: request)
            task.taskDescription = id
            task.resume()
        } else {
            let asset = AVURLAsset(url: stream.url, options: ["AVURLAssetHTTPHeaderFieldsKey": stream.headers])
            guard let session = hlsSession,
                  let task = session.makeAssetDownloadTask(
                    asset: asset, assetTitle: title, assetArtworkData: nil, options: nil) else {
                markFailed(id: id, message: "Download konnte nicht gestartet werden")
                return
            }
            task.taskDescription = id
            task.resume()
        }
    }

    private func cancelSessionTasks(id: String) {
        Task {
            var all: [URLSessionTask] = []
            if let hlsSession { all.append(contentsOf: await hlsSession.allTasks) }
            if let fileSession { all.append(contentsOf: await fileSession.allTasks) }
            for task in all where task.taskDescription == id {
                task.cancel()
            }
        }
    }

    // MARK: Callbacks from the session delegate

    func updateProgress(id: String, fraction: Double) {
        guard var job = jobs[id], job.status == .active else { return }
        job.progress = max(0, min(1, fraction))
        jobs[id] = job
    }

    func finished(id: String, location: URL, kind: DownloadKind) {
        guard let job = jobs[id] else {
            // Cancelled meanwhile: drop the data.
            try? FileManager.default.removeItem(at: location)
            return
        }
        resolveTasks[id] = nil
        let record = DownloadRecord(
            id: id, series: job.series, episode: job.episode, language: job.language,
            hoster: job.currentHoster ?? "", relativePath: DownloadPaths.relativePath(for: location),
            kind: kind, sizeBytes: 0, createdAt: Date(), isCompressed: false)
        records.removeAll { $0.id == id }
        records.append(record)
        jobs[id] = nil
        saveIndex()
        pump()

        Task { [weak self] in
            guard let self else { return }
            var finalLocation = location
            var wasCompressed = false

            // Compress MP4 files using hardware encoder if compression is enabled
            if kind == .file && self.settings.compressDownloads {
                if let compressed = await self.compressVideoFile(at: location) {
                    finalLocation = compressed
                    wasCompressed = true
                }
            }

            let size = await Task.detached(priority: .utility) { DownloadPaths.diskSize(of: finalLocation) }.value
            self.finalizeRecord(id: id, location: finalLocation, size: size, isCompressed: wasCompressed)
        }
    }

    private func finalizeRecord(id: String, location: URL, size: Int64, isCompressed: Bool) {
        guard let index = records.firstIndex(where: { $0.id == id }) else { return }
        records[index].sizeBytes = size
        records[index].relativePath = DownloadPaths.relativePath(for: location)
        records[index].isCompressed = isCompressed
        saveIndex()
    }

    /// Compresses a video file to a high-efficiency format (HEVC / 720p) to reduce disk space by 50-75%.
    private func compressVideoFile(at source: URL) async -> URL? {
        let destination = source.deletingPathExtension().appendingPathExtension("compressed.mp4")
        if FileManager.default.fileExists(atPath: destination.path) {
            try? FileManager.default.removeItem(at: destination)
        }
        let asset = AVURLAsset(url: source)
        let preferredPreset: String
        let fallbackPreset: String
        switch settings.downloadQuality {
        case .low:
            preferredPreset = AVAssetExportPreset640x480
            fallbackPreset = AVAssetExportPreset640x480
        case .medium:
            preferredPreset = AVAssetExportPresetHEVC1280x720
            fallbackPreset = AVAssetExportPreset1280x720
        case .high:
            preferredPreset = AVAssetExportPresetHEVC1920x1080
            fallbackPreset = AVAssetExportPreset1920x1080
        }
        let supportedPresets = AVAssetExportSession.exportPresets(compatibleWith: asset)
        let preset: String
        if supportedPresets.contains(preferredPreset) {
            preset = preferredPreset
        } else if supportedPresets.contains(fallbackPreset) {
            preset = fallbackPreset
        } else if supportedPresets.contains(AVAssetExportPresetMediumQuality) {
            preset = AVAssetExportPresetMediumQuality
        } else {
            return nil
        }

        guard let session = AVAssetExportSession(asset: asset, presetName: preset) else { return nil }
        session.outputURL = destination
        session.outputFileType = .mp4
        session.shouldOptimizeForNetworkUse = true
        await session.export()
        if session.status == .completed && FileManager.default.fileExists(atPath: destination.path) {
            let fm = FileManager.default
            try? fm.removeItem(at: source)
            try? fm.moveItem(at: destination, to: source)
            DownloadPaths.excludeFromBackup(source)
            return source
        }
        try? FileManager.default.removeItem(at: destination)
        return nil
    }

    private func setSize(_ size: Int64, id: String) {
        guard let index = records.firstIndex(where: { $0.id == id }) else { return }
        records[index].sizeBytes = size
        saveIndex()
    }

    /// Transfer failed: try the next hoster, or give up after a few attempts.
    func failed(id: String, message: String) {
        guard var job = jobs[id], job.status == .active else { return }
        resolveTasks[id] = nil
        if let hoster = job.currentHoster, !job.triedHosters.contains(hoster) {
            job.triedHosters.append(hoster)
        }
        job.currentHoster = nil
        job.progress = 0
        job.errorMessage = message
        if job.triedHosters.count < Self.maxHosterAttempts {
            job.status = .queued
        } else {
            job.status = .failed
        }
        jobs[id] = job
        saveIndex()
        pump()
    }

    private func markFailed(id: String, message: String) {
        guard var job = jobs[id] else { return }
        resolveTasks[id] = nil
        job.status = .failed
        job.progress = 0
        job.errorMessage = message
        jobs[id] = job
        saveIndex()
        pump()
    }

    // MARK: Relaunch

    /// Reconnects to tasks of the background sessions that kept running while the app was gone.
    private func restoreTasks() async {
        var all: [URLSessionTask] = []
        if let hlsSession { all.append(contentsOf: await hlsSession.allTasks) }
        if let fileSession { all.append(contentsOf: await fileSession.allTasks) }
        var running = Set<String>()
        for task in all {
            if let id = task.taskDescription, jobs[id]?.status == .active {
                running.insert(id)
            } else {
                task.cancel()
            }
        }
        for id in Array(jobs.keys) {
            guard var job = jobs[id], job.status == .active, !running.contains(id) else { continue }
            job.status = .queued
            job.progress = 0
            jobs[id] = job
        }
        restored = true
        saveIndex()
        pump()
    }

    // MARK: Persistence

    private func loadIndex() {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let data = try? Data(contentsOf: DownloadPaths.indexURL),
              let index = try? decoder.decode(DownloadIndex.self, from: data) else { return }
        // Drop entries whose files were purged.
        records = index.records.filter {
            FileManager.default.fileExists(atPath: DownloadPaths.absoluteURL($0.relativePath).path)
        }
        var loaded: [String: DownloadJob] = [:]
        for job in index.jobs where !records.contains(where: { $0.id == job.id }) {
            loaded[job.id] = job
        }
        jobs = loaded
    }

    private func saveIndex() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let index = DownloadIndex(records: records, jobs: Array(jobs.values))
        guard let data = try? encoder.encode(index) else { return }
        try? data.write(to: DownloadPaths.indexURL, options: .atomic)
    }

    private static func message(for error: Error) -> String {
        if let a = error as? AniworldError {
            switch a {
            case .noPlayableStream: return "Kein abspielbarer Stream gefunden"
            case .cloudflareChallenge: return "Cloudflare-Prüfung – bitte später erneut versuchen"
            case .http(let status, _): return "Serverfehler (\(status))"
            case .parsing: return "Seite konnte nicht gelesen werden"
            case .cancelled: return "Abgebrochen"
            }
        }
        return error.localizedDescription
    }
}
