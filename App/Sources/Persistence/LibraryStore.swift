import Foundation
import Observation
import UIKit
import AniworldKit

/// Local library: favorites, continue-watching history and per-episode progress.
/// Persisted as JSON in Application Support. Owned by Agent C; the public API
/// below is the contract the UI codes against — extend it, don't break it.
@MainActor
@Observable
final class LibraryStore {
    /// Saved series, newest first.
    private(set) var favorites: [FavoriteEntry] = []
    /// "Weiterschauen", newest first, one entry per series.
    private(set) var history: [WatchEntry] = []
    /// Progress per `EpisodeRef.id`.
    private(set) var progressByEpisode: [String: EpisodeProgress] = [:]
    /// Preferred language per series slug.
    private(set) var languageBySlug: [String: StreamLanguage] = [:]
    /// User-defined intro/outro times, keyed by `CustomSkip.key`.
    private(set) var customSkips: [String: CustomSkip] = [:]
    /// Series for which the "Kein Intro hinterlegt" prompt is switched off (local only).
    private(set) var mutedSkipPromptSlugs: Set<String> = []
    /// Series for which the user turned the online AniSkip lookup off (wrong match etc.).
    private(set) var onlineSkipDisabledSlugs: Set<String> = []

    // Sync bookkeeping (not shown in the UI).
    @ObservationIgnored private var languageTimes: [String: Date] = [:]
    @ObservationIgnored private var favoriteTombstones: [String: Date] = [:]
    @ObservationIgnored private var historyTombstones: [String: Date] = [:]
    @ObservationIgnored private var historyClearedAt: Date?
    @ObservationIgnored private var resetAt: Date?
    @ObservationIgnored private var customSkipTombstones: [String: Date] = [:]

    /// Called (on the main actor) after every local change made through the public API.
    /// Not called for changes applied by `apply(merged:)`.
    @ObservationIgnored var onChange: (() -> Void)?

    @ObservationIgnored private let fileURL: URL?
    @ObservationIgnored private var saveTask: Task<Void, Never>?
    @ObservationIgnored private var lifecycleTokens: [NSObjectProtocol] = []

    private static let historyLimit = 50

    private struct Snapshot: Codable {
        var favorites: [FavoriteEntry] = []
        var history: [WatchEntry] = []
        var progress: [String: EpisodeProgress] = [:]
        var languages: [String: StreamLanguage] = [:]
        var languageTimes: [String: Date] = [:]
        var favoriteTombstones: [String: Date] = [:]
        var historyTombstones: [String: Date] = [:]
        var historyClearedAt: Date?
        var resetAt: Date?
        var customSkips: [CustomSkip] = []
        var customSkipTombstones: [String: Date] = [:]
        var mutedSkipPromptSlugs: [String] = []
        var onlineSkipDisabledSlugs: [String] = []

        init() {}

        enum CodingKeys: String, CodingKey {
            case favorites, history, progress, languages
            case languageTimes, favoriteTombstones, historyTombstones, historyClearedAt, resetAt
            case customSkips, customSkipTombstones, mutedSkipPromptSlugs, onlineSkipDisabledSlugs
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            favorites = try c.decodeIfPresent([FavoriteEntry].self, forKey: .favorites) ?? []
            history = try c.decodeIfPresent([WatchEntry].self, forKey: .history) ?? []
            progress = try c.decodeIfPresent([String: EpisodeProgress].self, forKey: .progress) ?? [:]
            languages = try c.decodeIfPresent([String: StreamLanguage].self, forKey: .languages) ?? [:]
            languageTimes = try c.decodeIfPresent([String: Date].self, forKey: .languageTimes) ?? [:]
            favoriteTombstones = try c.decodeIfPresent([String: Date].self, forKey: .favoriteTombstones) ?? [:]
            historyTombstones = try c.decodeIfPresent([String: Date].self, forKey: .historyTombstones) ?? [:]
            historyClearedAt = try c.decodeIfPresent(Date.self, forKey: .historyClearedAt)
            resetAt = try c.decodeIfPresent(Date.self, forKey: .resetAt)
            customSkips = try c.decodeIfPresent([CustomSkip].self, forKey: .customSkips) ?? []
            customSkipTombstones = try c.decodeIfPresent([String: Date].self, forKey: .customSkipTombstones) ?? [:]
            mutedSkipPromptSlugs = try c.decodeIfPresent([String].self, forKey: .mutedSkipPromptSlugs) ?? []
            onlineSkipDisabledSlugs = try c.decodeIfPresent([String].self, forKey: .onlineSkipDisabledSlugs) ?? []
        }
    }

    /// - Parameter fileURL: override for tests/previews; default is Application Support/library.json.
    init(fileURL: URL? = LibraryStore.defaultFileURL()) {
        self.fileURL = fileURL
        load()
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
        return base.appendingPathComponent("library.json")
    }

    private func load() {
        guard let fileURL, let data = try? Data(contentsOf: fileURL),
              let snap = try? JSONDecoder().decode(Snapshot.self, from: data) else { return }
        favorites = snap.favorites
        history = snap.history
        progressByEpisode = snap.progress
        languageBySlug = snap.languages
        languageTimes = snap.languageTimes
        favoriteTombstones = snap.favoriteTombstones
        historyTombstones = snap.historyTombstones
        historyClearedAt = snap.historyClearedAt
        resetAt = snap.resetAt
        customSkips = Dictionary(snap.customSkips.map { ($0.key, $0) }, uniquingKeysWith: { a, _ in a })
        customSkipTombstones = snap.customSkipTombstones
        mutedSkipPromptSlugs = Set(snap.mutedSkipPromptSlugs)
        onlineSkipDisabledSlugs = Set(snap.onlineSkipDisabledSlugs)
    }

    /// Schedules a debounced disk write. `notify: false` is used for changes that came from sync.
    private func scheduleSave(notify: Bool = true) {
        if notify { onChange?() }
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            guard !Task.isCancelled else { return }
            self?.flush()
        }
    }

    /// Writes the library to disk immediately (call when the app goes to the background).
    func flush() {
        saveTask?.cancel()
        saveTask = nil
        guard let fileURL else { return }
        var snap = Snapshot()
        snap.favorites = favorites
        snap.history = history
        snap.progress = progressByEpisode
        snap.languages = languageBySlug
        snap.languageTimes = languageTimes
        snap.favoriteTombstones = favoriteTombstones
        snap.historyTombstones = historyTombstones
        snap.historyClearedAt = historyClearedAt
        snap.resetAt = resetAt
        snap.customSkips = customSkips.values.sorted { $0.key < $1.key }
        snap.customSkipTombstones = customSkipTombstones
        snap.mutedSkipPromptSlugs = mutedSkipPromptSlugs.sorted()
        snap.onlineSkipDisabledSlugs = onlineSkipDisabledSlugs.sorted()
        guard let data = try? JSONEncoder().encode(snap) else { return }
        try? data.write(to: fileURL, options: [.atomic])
    }

    // MARK: Favorites

    func isFavorite(_ slug: String) -> Bool {
        favorites.contains { $0.series.slug == slug }
    }

    func toggleFavorite(_ series: SeriesSummary) {
        if isFavorite(series.slug) {
            removeFavorite(series.slug)
        } else {
            favorites.insert(FavoriteEntry(series: series, addedAt: Date()), at: 0)
            scheduleSave()
        }
    }

    func removeFavorite(_ slug: String) {
        favorites.removeAll { $0.series.slug == slug }
        favoriteTombstones[slug] = Date()
        scheduleSave()
    }

    // MARK: Progress & history

    func progress(for episode: EpisodeRef) -> EpisodeProgress? {
        progressByEpisode[episode.id]
    }

    /// Called periodically by the player and when playback stops.
    func updateProgress(series: SeriesSummary, episode: EpisodeRef, language: StreamLanguage?,
                        position: Double, duration: Double) {
        guard position.isFinite, position >= 0 else { return }
        let duration = duration.isFinite && duration > 0 ? duration : 0
        let now = Date()
        let finished = duration > 0 && (position / duration >= 0.9 || duration - position < 60)

        var p = progressByEpisode[episode.id]
            ?? EpisodeProgress(position: 0, duration: 0, watched: false, updatedAt: now)
        p.position = position
        if duration > 0 { p.duration = duration }
        p.watched = p.watched || finished
        p.updatedAt = now
        progressByEpisode[episode.id] = p

        upsertHistory(WatchEntry(series: series, episode: episode, language: language,
                                 position: position, duration: p.duration,
                                 updatedAt: now, isFinished: finished))
        if let language {
            languageBySlug[series.slug] = language
            languageTimes[series.slug] = now
        }
        scheduleSave()
    }

    func setWatched(_ watched: Bool, episode: EpisodeRef, series: SeriesSummary) {
        let now = Date()
        var p = progressByEpisode[episode.id]
            ?? EpisodeProgress(position: 0, duration: 0, watched: false, updatedAt: now)
        p.watched = watched
        p.updatedAt = now
        if watched {
            if p.duration > 0 { p.position = p.duration }
            progressByEpisode[episode.id] = p
            if !hasLaterHistoryEntry(than: episode) {
                upsertHistory(WatchEntry(series: series, episode: episode,
                                         language: languageBySlug[series.slug],
                                         position: p.position, duration: p.duration,
                                         updatedAt: now, isFinished: true))
            }
        } else {
            p.position = 0
            progressByEpisode[episode.id] = p
            if let entry = history.first(where: { $0.series.slug == series.slug }),
               entry.episode.id == episode.id {
                history.removeAll { $0.series.slug == series.slug }
                historyTombstones[series.slug] = now
            }
        }
        scheduleSave()
    }

    /// Marks all episodes up to and including `episode` in its season as watched.
    func markWatchedUpTo(_ episode: EpisodeRef, in episodes: [EpisodeRef], series: SeriesSummary) {
        let now = Date()
        var targets = episodes.filter { $0.season == episode.season && $0.number <= episode.number }
        if !targets.contains(where: { $0.id == episode.id }) { targets.append(episode) }
        for ep in targets {
            var p = progressByEpisode[ep.id]
                ?? EpisodeProgress(position: 0, duration: 0, watched: false, updatedAt: now)
            p.watched = true
            if p.duration > 0 { p.position = p.duration }
            p.updatedAt = now
            progressByEpisode[ep.id] = p
        }
        if !hasLaterHistoryEntry(than: episode) {
            let p = progressByEpisode[episode.id]
            upsertHistory(WatchEntry(series: series, episode: episode,
                                     language: languageBySlug[series.slug],
                                     position: p?.position ?? 0, duration: p?.duration ?? 0,
                                     updatedAt: now, isFinished: true))
        }
        scheduleSave()
    }

    /// Marks the given episodes as watched (e.g. a season or series already seen elsewhere).
    /// "Weiterschauen" then points at the last of them, so the next episode comes up.
    func markWatched(_ episodes: [EpisodeRef], series: SeriesSummary) {
        guard !episodes.isEmpty else { return }
        let now = Date()
        for ep in episodes {
            var p = progressByEpisode[ep.id]
                ?? EpisodeProgress(position: 0, duration: 0, watched: false, updatedAt: now)
            p.watched = true
            if p.duration > 0 { p.position = p.duration }
            p.updatedAt = now
            progressByEpisode[ep.id] = p
        }
        let last = episodes.max { ($0.season, $0.number) < ($1.season, $1.number) }!
        if !hasLaterHistoryEntry(than: last) {
            let p = progressByEpisode[last.id]
            upsertHistory(WatchEntry(series: series, episode: last,
                                     language: languageBySlug[series.slug],
                                     position: p?.position ?? 0, duration: p?.duration ?? 0,
                                     updatedAt: now, isFinished: true))
        }
        scheduleSave()
    }

    /// Whether every given episode is marked watched.
    func allWatched(_ episodes: [EpisodeRef]) -> Bool {
        !episodes.isEmpty && episodes.allSatisfy { progressByEpisode[$0.id]?.watched == true }
    }

    /// Whether any episode of the series (or of one season) has progress or is marked watched.
    func hasProgress(seriesSlug: String, season: Int? = nil) -> Bool {
        progressByEpisode.contains { id, p in
            Self.matches(id, seriesSlug: seriesSlug, season: season) && (p.watched || p.position > 0)
        }
    }

    /// Resets position and watched state of one episode, a season or the whole series, e.g. to
    /// watch it again. Entries are kept with a new date (not deleted) so iCloud sync doesn't bring
    /// the old progress back from another device. The "Weiterschauen" entry goes too.
    func resetProgress(seriesSlug: String, season: Int? = nil, episodeID: String? = nil) {
        let now = Date()
        var changed = false
        for (id, var p) in progressByEpisode {
            if let episodeID { guard id == episodeID else { continue } }
            guard Self.matches(id, seriesSlug: seriesSlug, season: season), p.watched || p.position > 0 else { continue }
            p.position = 0
            p.watched = false
            p.updatedAt = now
            progressByEpisode[id] = p
            changed = true
        }
        if let entry = history.first(where: { $0.series.slug == seriesSlug }),
           episodeID.map({ $0 == entry.episode.id }) ?? Self.matches(entry.episode.id, seriesSlug: seriesSlug, season: season) {
            history.removeAll { $0.series.slug == seriesSlug }
            historyTombstones[seriesSlug] = now
            changed = true
        }
        if changed { scheduleSave() }
    }

    /// `EpisodeRef.id` is "<slug>-s<season>e<number>"; match exactly so "naruto" doesn't hit
    /// "naruto-shippuden".
    private static func matches(_ id: String, seriesSlug: String, season: Int?) -> Bool {
        let prefix = seriesSlug + "-s"
        guard id.hasPrefix(prefix) else { return false }
        let rest = id.dropFirst(prefix.count)
        guard let e = rest.firstIndex(of: "e"), let s = Int(rest[..<e]),
              Int(rest[rest.index(after: e)...]) != nil else { return false }
        return season.map { $0 == s } ?? true
    }

    func removeFromHistory(_ slug: String) {
        history.removeAll { $0.series.slug == slug }
        historyTombstones[slug] = Date()
        scheduleSave()
    }

    /// Clears the "Weiterschauen" list only; per-episode progress is kept.
    func clearHistory() {
        history.removeAll()
        historyClearedAt = Date()
        historyTombstones = [:]
        scheduleSave()
    }

    /// Most recent history entry for a series (for "Fortsetzen" on the detail page).
    func lastWatched(seriesSlug: String) -> WatchEntry? {
        history.first { $0.series.slug == seriesSlug }
    }

    /// Language last used for a series, to preselect it next time.
    func preferredLanguage(seriesSlug: String) -> StreamLanguage? {
        languageBySlug[seriesSlug]
    }

    func setPreferredLanguage(_ language: StreamLanguage, seriesSlug: String) {
        languageBySlug[seriesSlug] = language
        languageTimes[seriesSlug] = Date()
        scheduleSave()
    }

    // MARK: Custom skip times

    /// Entry that applies to an episode: the episode's own entry first, then the season's.
    func customSkip(seriesSlug: String, season: Int, episode: Int) -> CustomSkip? {
        customSkips[CustomSkip.key(seriesSlug: seriesSlug, season: season, episode: episode)]
            ?? customSkips[CustomSkip.key(seriesSlug: seriesSlug, season: season, episode: nil)]
    }

    /// All entries, sorted by series and position for display.
    var customSkipList: [CustomSkip] {
        customSkips.values.sorted { a, b in
            if a.seriesSlug != b.seriesSlug { return a.seriesSlug < b.seriesSlug }
            if a.season != b.season { return a.season < b.season }
            return (a.episode ?? -1) < (b.episode ?? -1)
        }
    }

    func setCustomSkip(_ skip: CustomSkip) {
        var skip = skip
        skip.updatedAt = Date()
        customSkips[skip.key] = skip
        customSkipTombstones[skip.key] = nil
        scheduleSave()
    }

    func removeCustomSkip(key: String) {
        guard customSkips[key] != nil else { return }
        customSkips[key] = nil
        customSkipTombstones[key] = Date()
        scheduleSave()
    }

    func isSkipPromptMuted(seriesSlug: String) -> Bool {
        mutedSkipPromptSlugs.contains(seriesSlug)
    }

    func muteSkipPrompt(seriesSlug: String) {
        guard !mutedSkipPromptSlugs.contains(seriesSlug) else { return }
        mutedSkipPromptSlugs.insert(seriesSlug)
        // Local preference: no sync notification needed, only persistence.
        scheduleSave(notify: false)
    }

    /// True when the user turned the online AniSkip lookup off for this series.
    func isOnlineSkipDisabled(seriesSlug: String) -> Bool {
        onlineSkipDisabledSlugs.contains(seriesSlug)
    }

    func setOnlineSkipDisabled(_ disabled: Bool, seriesSlug: String) {
        guard disabled != onlineSkipDisabledSlugs.contains(seriesSlug) else { return }
        if disabled { onlineSkipDisabledSlugs.insert(seriesSlug) } else { onlineSkipDisabledSlugs.remove(seriesSlug) }
        scheduleSave(notify: false)
    }

    func resetMutedSkipPrompts() {
        guard !mutedSkipPromptSlugs.isEmpty else { return }
        mutedSkipPromptSlugs = []
        scheduleSave(notify: false)
    }

    /// Best known title for a series slug (favorites, then history), if any.
    func knownTitle(forSlug slug: String) -> String? {
        favorites.first { $0.series.slug == slug }?.series.title
            ?? history.first { $0.series.slug == slug }?.series.title
    }

    /// Wipes favorites, history, progress and custom skip times.
    func resetAll() {
        favorites = []
        history = []
        progressByEpisode = [:]
        languageBySlug = [:]
        languageTimes = [:]
        favoriteTombstones = [:]
        historyTombstones = [:]
        historyClearedAt = nil
        customSkips = [:]
        customSkipTombstones = [:]
        mutedSkipPromptSlugs = []
        onlineSkipDisabledSlugs = []
        resetAt = Date()
        onChange?()
        flush()
    }

    // MARK: Sync support

    /// Everything the sync layer needs, as a plain value.
    func exportState() -> LibraryState {
        var langs: [String: LanguageChoice] = [:]
        for (slug, lang) in languageBySlug {
            langs[slug] = LanguageChoice(language: lang, updatedAt: languageTimes[slug] ?? .distantPast)
        }
        return LibraryState(
            favorites: favorites, favoriteTombstones: favoriteTombstones,
            history: history, historyTombstones: historyTombstones,
            historyClearedAt: historyClearedAt, progress: progressByEpisode,
            languages: langs, resetAt: resetAt,
            customSkips: customSkips.values.sorted { $0.key < $1.key },
            customSkipTombstones: customSkipTombstones
        )
    }

    /// Replaces the local library with a merged state. Does not trigger `onChange`.
    func apply(merged: LibraryState) {
        guard merged != exportState() else { return }
        favorites = merged.favorites
        favoriteTombstones = merged.favoriteTombstones
        history = merged.history
        historyTombstones = merged.historyTombstones
        historyClearedAt = merged.historyClearedAt
        progressByEpisode = merged.progress
        languageBySlug = merged.languages.mapValues { $0.language }
        languageTimes = merged.languages.mapValues { $0.updatedAt }
        resetAt = merged.resetAt
        customSkips = Dictionary(merged.customSkips.map { ($0.key, $0) }, uniquingKeysWith: { a, _ in a })
        customSkipTombstones = merged.customSkipTombstones
        scheduleSave(notify: false)
    }

    // MARK: Helpers

    private func upsertHistory(_ entry: WatchEntry) {
        history.removeAll { $0.series.slug == entry.series.slug }
        history.insert(entry, at: 0)
        if history.count > Self.historyLimit {
            history.removeLast(history.count - Self.historyLimit)
        }
    }

    /// True if the series' history entry already points at a later episode.
    private func hasLaterHistoryEntry(than episode: EpisodeRef) -> Bool {
        guard let entry = history.first(where: { $0.series.slug == episode.seriesSlug }) else { return false }
        let e = entry.episode
        if e.season == episode.season { return e.number > episode.number }
        if e.season == 0 || episode.season == 0 { return false }
        return e.season > episode.season
    }
}
