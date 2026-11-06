import Foundation
import Observation
import UIKit
import WidgetKit
import AniworldKit

/// Schreibt die Daten für die Home-Screen-Widgets (Streak, Weiterschauen, Statistik) als JSON in den
/// App-Group-Container und stößt danach das Neuladen der Widget-Timelines an.
/// Ohne App Group (z. B. beim Sideloaden ohne Entitlement) passiert nichts.
@MainActor
final class WidgetSnapshotWriter {
    private let stats: WatchStatsStore
    private let library: LibraryStore

    private var started = false
    private var debounceTask: Task<Void, Never>?
    private var tokens: [NSObjectProtocol] = []
    /// Zuletzt geschriebener Stand (mit `generatedAt` = distantPast), um unnötige Writes zu vermeiden.
    private var lastWritten: WidgetSnapshot?
    private var failedCovers = Set<String>()
    private var isWriting = false
    private var writeAgain = false

    private static let coverMaxWidth: CGFloat = 300
    private static let maxContinueItems = 4

    init(stats: WatchStatsStore, library: LibraryStore) {
        self.stats = stats
        self.library = library
    }

    // MARK: Lifecycle

    /// Beginnt die Änderungen zu beobachten und schreibt einmal den aktuellen Stand.
    func start() {
        guard !started else { return }
        started = true
        armObservation()
        let token = NotificationCenter.default.addObserver(
            forName: .NSCalendarDayChanged, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.scheduleUpdate() }
        }
        tokens.append(token)
        scheduleUpdate()
    }

    /// App wird aktiv: Stand prüfen (z. B. neuer Tag).
    func appBecameActive() {
        scheduleUpdate()
    }

    /// App geht in den Hintergrund: sofort schreiben (mit kurzer Hintergrundzeit).
    func flush() {
        debounceTask?.cancel()
        debounceTask = nil
        var bgTask = UIBackgroundTaskIdentifier.invalid
        bgTask = UIApplication.shared.beginBackgroundTask(withName: "widget-snapshot") {
            UIApplication.shared.endBackgroundTask(bgTask)
            bgTask = .invalid
        }
        Task { [weak self] in
            await self?.writeNow()
            if bgTask != .invalid { UIApplication.shared.endBackgroundTask(bgTask) }
        }
    }

    // MARK: Triggers

    /// Beobachtet Sessions und Verlauf; `withObservationTracking` feuert nur einmal, daher neu setzen.
    private func armObservation() {
        withObservationTracking {
            _ = stats.sessions
            _ = library.history
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.armObservation()
                self.scheduleUpdate()
            }
        }
    }

    private func scheduleUpdate() {
        debounceTask?.cancel()
        debounceTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            guard !Task.isCancelled else { return }
            await self?.writeNow()
        }
    }

    // MARK: Build + write

    private func writeNow() async {
        guard WidgetShared.containerURL != nil else { return }
        // Nicht parallel schreiben; währenddessen eingehende Änderungen holen wir danach nach.
        if isWriting { writeAgain = true; return }
        isWriting = true
        defer { isWriting = false }
        repeat {
            writeAgain = false
            await buildAndWrite()
        } while writeAgain
    }

    private func buildAndWrite() async {
        guard let coversDir = WidgetShared.coversDirectory else { return }
        if lastWritten == nil, var disk = WidgetShared.loadSnapshot() {
            disk.generatedAt = .distantPast
            lastWritten = disk
        }

        let entries = continueEntries()
        try? FileManager.default.createDirectory(at: coversDir, withIntermediateDirectories: true)

        // Erst mit vorhandenen Covern schreiben, damit Streak/Statistik nicht auf Downloads warten.
        write(makeSnapshot(entries: entries, coversDir: coversDir))

        var downloaded = false
        for entry in entries {
            let name = Self.coverFileName(slug: entry.series.slug)
            let file = coversDir.appendingPathComponent(name)
            guard let url = entry.series.coverURL, !FileManager.default.fileExists(atPath: file.path),
                  !failedCovers.contains(name) else { continue }
            if await Self.downloadCover(from: url, to: file) {
                downloaded = true
            } else {
                failedCovers.insert(name)
            }
        }
        if downloaded { write(makeSnapshot(entries: entries, coversDir: coversDir)) }

        removeUnusedCovers(in: coversDir, keeping: Set(entries.map { Self.coverFileName(slug: $0.series.slug) }))
    }

    private func continueEntries() -> [WatchEntry] {
        Array(
            library.history
                .filter { !$0.isFinished }
                .sorted { $0.updatedAt > $1.updatedAt }
                .prefix(Self.maxContinueItems)
        )
    }

    private func makeSnapshot(entries: [WatchEntry], coversDir: URL) -> WidgetSnapshot {
        let now = Date()
        let calendar = Calendar.current
        var snap = WidgetSnapshot()
        snap.generatedAt = now

        let streak = stats.streak(now: now, calendar: calendar)
        snap.streak.current = streak.current
        snap.streak.longest = streak.longest
        snap.streak.todayDone = streak.todayDone
        snap.streak.lastSevenDays = streak.lastSevenDays.map { WidgetSnapshot.Day(date: $0.date, done: $0.done) }

        // Woche: immer Montag bis Sonntag (passend zum Mo–So-Diagramm); Monat: wie in der Statistik.
        var mondayCalendar = calendar
        mondayCalendar.firstWeekday = 2
        let weekInterval = mondayCalendar.dateInterval(of: .weekOfYear, for: now)
            ?? DateInterval(start: calendar.startOfDay(for: now), duration: 7 * 86_400)
        let week = WatchStatsCalculator(sessions: stats.sessions, interval: weekInterval, calendar: calendar,
                                        seriesMeta: stats.seriesMeta).compute()
        snap.week = Self.period(from: week)
        let month = stats.stats(for: StatsPeriod.month(containing: now, calendar: calendar), calendar: calendar)
        snap.month = Self.period(from: month)

        snap.continueWatching = entries.map { entry in
            let name = Self.coverFileName(slug: entry.series.slug)
            let hasCover = entry.series.coverURL != nil
                && FileManager.default.fileExists(atPath: coversDir.appendingPathComponent(name).path)
            return WidgetSnapshot.ContinueItem(
                slug: entry.series.slug,
                title: entry.series.title,
                episodeLabel: Self.episodeLabel(entry.episode),
                progress: entry.fraction,
                remainingSeconds: entry.remaining,
                updatedAt: entry.updatedAt,
                coverFileName: hasCover ? name : nil
            )
        }
        return snap
    }

    private static func period(from stats: WatchStats) -> WidgetSnapshot.Period {
        var p = WidgetSnapshot.Period()
        p.totalSeconds = stats.totalSeconds
        p.completedEpisodes = stats.completedEpisodeCount
        p.seriesCount = stats.seriesCount
        p.topSeriesTitle = stats.topSeries.first?.title
        p.weekdaySeconds = stats.weekdaySeconds
        return p
    }

    /// "S1 · F5" bzw. "Film 2".
    private static func episodeLabel(_ episode: EpisodeRef) -> String {
        episode.season == 0 ? "Film \(episode.number)" : "S\(episode.season) · F\(episode.number)"
    }

    /// Schreibt atomar, aber nur wenn sich der Inhalt (ohne `generatedAt`) geändert hat.
    private func write(_ snapshot: WidgetSnapshot) {
        guard let url = WidgetShared.snapshotURL else { return }
        var normalized = snapshot
        normalized.generatedAt = .distantPast
        guard normalized != lastWritten else { return }
        guard let data = WidgetShared.encode(snapshot) else { return }
        do {
            try data.write(to: url, options: [.atomic])
        } catch {
            return
        }
        lastWritten = normalized
        WidgetCenter.shared.reloadAllTimelines()
    }

    // MARK: Covers

    /// Dateiname aus dem Slug: nur Buchstaben, Ziffern, "-" und "_".
    private static func coverFileName(slug: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        var cleaned = ""
        for scalar in slug.unicodeScalars {
            cleaned.append(allowed.contains(scalar) ? Character(scalar) : "_")
        }
        return (cleaned.isEmpty ? "cover" : cleaned) + ".jpg"
    }

    private static func downloadCover(from url: URL, to file: URL) async -> Bool {
        guard let (data, response) = try? await URLSession.shared.data(from: url) else { return false }
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) { return false }
        guard let image = UIImage(data: data) else { return false }
        let scaled = downscale(image, maxWidth: coverMaxWidth)
        guard let jpeg = scaled.jpegData(compressionQuality: 0.8) else { return false }
        do {
            try jpeg.write(to: file, options: [.atomic])
            return true
        } catch {
            return false
        }
    }

    private static func downscale(_ image: UIImage, maxWidth: CGFloat) -> UIImage {
        let size = image.size
        guard size.width > maxWidth, size.width > 0 else { return image }
        let target = CGSize(width: maxWidth, height: (size.height * maxWidth / size.width).rounded())
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        return UIGraphicsImageRenderer(size: target, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
    }

    private func removeUnusedCovers(in dir: URL, keeping names: Set<String>) {
        let files = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
        for file in files where !names.contains(file) {
            try? FileManager.default.removeItem(at: dir.appendingPathComponent(file))
        }
    }
}
