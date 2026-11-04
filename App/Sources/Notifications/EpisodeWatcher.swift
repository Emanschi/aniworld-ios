import Foundation
import Observation
import BackgroundTasks
import UserNotifications
import AniworldKit

/// Prüft Favoriten lokal (ohne Server) auf neue Folgen/Staffeln/Filme und meldet sie per
/// lokaler Mitteilung. Auslöser: BGAppRefreshTask und App-Aktivierung (höchstens alle ~30 Min.).
@MainActor
@Observable
final class EpisodeWatcher {
    static let refreshTaskIdentifier = "com.aniworldios.app.refresh"

    private(set) var isChecking = false
    private(set) var lastCheckAt: Date?
    private(set) var authorizationStatus: UNAuthorizationStatus = .notDetermined
    /// Von einem Tap auf eine Mitteilung gesetzt; die Oberfläche öffnet die Serie und setzt es zurück.
    var pendingOpenSeries: SeriesSummary?

    @ObservationIgnored private let service: AniworldService
    @ObservationIgnored private let library: LibraryStore
    @ObservationIgnored private let settings: SettingsStore
    @ObservationIgnored private let snapshots: EpisodeSnapshotStore
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let notificationDelegate = NotificationDelegate()

    private static let maxSeriesPerRun = 30
    private static let activeCheckInterval: TimeInterval = 30 * 60
    private static let lastCheckKey = "episodeWatcher.lastCheckAt"
    private static let lastAutoRunKey = "episodeWatcher.lastAutoRunAt"

    init(service: AniworldService, library: LibraryStore, settings: SettingsStore,
         snapshots: EpisodeSnapshotStore = EpisodeSnapshotStore(), defaults: UserDefaults = .standard) {
        self.service = service
        self.library = library
        self.settings = settings
        self.snapshots = snapshots
        self.defaults = defaults
        if let stored = defaults.object(forKey: Self.lastCheckKey) as? Date { lastCheckAt = stored }
    }

    // MARK: Setup

    /// Muss beim Start (`App.init`) aufgerufen werden, bevor die App fertig gestartet ist.
    func configure() {
        notificationDelegate.onOpenSeries = { [weak self] (summary: SeriesSummary) in
            self?.pendingOpenSeries = summary
        }
        UNUserNotificationCenter.current().delegate = notificationDelegate
        BGTaskScheduler.shared.register(forTaskWithIdentifier: Self.refreshTaskIdentifier, using: nil) { [weak self] (task: BGTask) in
            guard let refreshTask = task as? BGAppRefreshTask else {
                task.setTaskCompleted(success: false)
                return
            }
            Task { @MainActor in
                if let self = self {
                    self.handleBackgroundRefresh(refreshTask)
                } else {
                    refreshTask.setTaskCompleted(success: false)
                }
            }
        }
        Task { await refreshAuthorizationStatus() }
    }

    // MARK: Authorization

    func refreshAuthorizationStatus() async {
        let current: UNNotificationSettings = await UNUserNotificationCenter.current().notificationSettings()
        authorizationStatus = current.authorizationStatus
    }

    /// Fragt die Berechtigung an. Gibt `true` zurück, wenn Mitteilungen erlaubt sind.
    func requestAuthorization() async -> Bool {
        let granted: Bool = (try? await UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        await refreshAuthorizationStatus()
        return granted
    }

    // MARK: Triggers

    var isBackgroundWorkEnabled: Bool { settings.notifyNewEpisodes || settings.notifyAppUpdates }

    /// Beim Wechsel der App in den Hintergrund aufrufen.
    func scheduleBackgroundRefresh() {
        guard isBackgroundWorkEnabled else {
            BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: Self.refreshTaskIdentifier)
            return
        }
        let request = BGAppRefreshTaskRequest(identifier: Self.refreshTaskIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 3 * 60 * 60)
        try? BGTaskScheduler.shared.submit(request)
    }

    /// Beim Aktivieren der App: prüft, wenn die letzte automatische Prüfung länger als ~30 Min. her ist.
    func runIfDue() async {
        await refreshAuthorizationStatus()
        guard isBackgroundWorkEnabled, !isChecking else { return }
        if let last = defaults.object(forKey: Self.lastAutoRunKey) as? Date,
           Date().timeIntervalSince(last) < Self.activeCheckInterval { return }
        await runAllChecks()
    }

    private func handleBackgroundRefresh(_ task: BGAppRefreshTask) {
        scheduleBackgroundRefresh()
        let work = Task { @MainActor in
            await self.runAllChecks()
            task.setTaskCompleted(success: !Task.isCancelled)
        }
        task.expirationHandler = {
            work.cancel()
        }
    }

    private func runAllChecks() async {
        defaults.set(Date(), forKey: Self.lastAutoRunKey)
        if settings.notifyNewEpisodes {
            _ = await checkNow()
        }
        if settings.notifyAppUpdates, !Task.isCancelled {
            await AppUpdateChecker.shared.checkAndNotify()
        }
    }

    // MARK: Check

    /// Prüft die Favoriten nacheinander. Gibt die Zahl neu entdeckter Folgen zurück.
    @discardableResult
    func checkNow() async -> Int {
        guard !isChecking else { return 0 }
        isChecking = true
        defer {
            isChecking = false
            let now = Date()
            lastCheckAt = now
            defaults.set(now, forKey: Self.lastCheckKey)
        }

        let favorites: [FavoriteEntry] = library.favorites
        snapshots.prune(keeping: Set(favorites.map { $0.series.slug }))

        // Am längsten ungeprüfte Serien zuerst (neue Favoriten ohne Eintrag ganz vorne).
        let ordered: [FavoriteEntry] = favorites.sorted { (a: FavoriteEntry, b: FavoriteEntry) -> Bool in
            let da: Date = snapshots.entry(for: a.series.slug)?.checkedAt ?? Date.distantPast
            let db: Date = snapshots.entry(for: b.series.slug)?.checkedAt ?? Date.distantPast
            return da < db
        }
        let batch: [FavoriteEntry] = Array(ordered.prefix(Self.maxSeriesPerRun))

        var total = 0
        var first = true
        for favorite in batch {
            if Task.isCancelled { break }
            if !first { try? await Task.sleep(nanoseconds: 400_000_000) }
            first = false
            let found: [EpisodeRef]? = await checkSeries(favorite.series)
            if let found = found, !found.isEmpty {
                total += found.count
                await postNotification(series: favorite.series, episodes: found)
            }
        }
        snapshots.save()
        return total
    }

    /// Gibt `nil` bei Fehlern zurück (Snapshot bleibt dann unverändert), sonst die neuen Folgen.
    private func checkSeries(_ series: SeriesSummary) async -> [EpisodeRef]? {
        do {
            let detail: SeriesDetail = try await service.seriesDetail(slug: series.slug)
            let seasonNumbers: [Int] = detail.seasons.map { $0.number }
            guard !seasonNumbers.isEmpty else { return nil }

            let previous: EpisodeSnapshotEntry? = snapshots.entry(for: series.slug)
            var counts: [String: Int] = previous?.counts ?? [:]
            let isBaseline: Bool = (previous == nil)

            // Zu prüfen: höchste Staffel, Filme (0) und jede bisher unbekannte Staffel.
            var toFetch: Set<Int> = []
            if let highest = seasonNumbers.filter({ $0 > 0 }).max() { toFetch.insert(highest) }
            if seasonNumbers.contains(0) { toFetch.insert(0) }
            if !isBaseline {
                for number in seasonNumbers where counts[String(number)] == nil { toFetch.insert(number) }
            }

            var newEpisodes: [EpisodeRef] = []
            for number in toFetch.sorted() {
                if Task.isCancelled { return nil }
                let fetched: [EpisodeRef] = try await service.episodes(slug: series.slug, season: number)
                let episodes: [EpisodeRef] = fetched.sorted { $0.number < $1.number }
                let old: Int? = counts[String(number)]
                if let old = old, old >= 0 {
                    if episodes.count > old { newEpisodes.append(contentsOf: Array(episodes.dropFirst(old))) }
                    counts[String(number)] = max(old, episodes.count)
                } else if old == nil && !isBaseline {
                    // Komplett neue Staffel bzw. neuer Filmbereich.
                    newEpisodes.append(contentsOf: episodes)
                    counts[String(number)] = episodes.count
                } else {
                    // Baseline oder Staffel ohne erfasste Anzahl: nur merken.
                    counts[String(number)] = episodes.count
                }
            }
            // Übrige bekannte Staffeln ohne Zählung vormerken, damit sie später nicht als neu gelten.
            for number in seasonNumbers where counts[String(number)] == nil {
                counts[String(number)] = -1
            }

            snapshots.set(EpisodeSnapshotEntry(counts: counts, checkedAt: Date()), for: series.slug)
            return newEpisodes
        } catch {
            return nil
        }
    }

    // MARK: Notifications

    private func postNotification(series: SeriesSummary, episodes: [EpisodeRef]) async {
        await refreshAuthorizationStatus()
        guard authorizationStatus == .authorized || authorizationStatus == .provisional else { return }

        let content = UNMutableNotificationContent()
        if episodes.count == 1, let episode = episodes.first {
            content.title = "Neue Folge: \(series.title)"
            let name: String = episode.title.isEmpty ? episode.code : "\(episode.code) – \(episode.title)"
            content.body = "\(name) ist jetzt verfügbar"
        } else {
            content.title = "Neue Folgen: \(series.title)"
            content.body = "\(episodes.count) neue Folgen sind jetzt verfügbar"
        }
        content.sound = .default
        content.threadIdentifier = series.slug
        content.userInfo = ["slug": series.slug, "title": series.title, "url": series.url.absoluteString]

        let request = UNNotificationRequest(
            identifier: "new-episodes-\(series.slug)-\(Int(Date().timeIntervalSince1970))",
            content: content, trigger: nil)
        try? await UNUserNotificationCenter.current().add(request)
    }
}
