import AVFoundation
import Foundation
import Observation
import AniworldKit

/// Drives one player screen: resolves a stream, owns the `AVPlayer`, saves progress,
/// handles hoster/language switching, hoster fallback and autoplay of the next episode.
@MainActor
@Observable
final class PlayerViewModel {
    enum State: Equatable {
        case loading(String)
        case playing
        case error(String)
    }

    // Observed by the UI
    var state: State = .loading("Lade Hoster…")
    var series: SeriesSummary
    var episode: EpisodeRef
    var seasonEpisodes: [EpisodeRef]
    var currentLanguage: StreamLanguage?
    var currentHoster: String?
    var availableLanguages: [StreamLanguage] = []
    var availableHosters: [String] = []
    var position: Double = 0
    var duration: Double = 0
    var isPaused = false
    var controlsVisible = true
    var isPictureInPictureActive = false
    /// Seconds left of the autoplay countdown, nil when inactive.
    var countdown: Int?
    var hasNext = false
    /// True once an item was attached to the player (the native view is shown from then on).
    var hasItem = false

    let player = AVPlayer()

    // Internals
    @ObservationIgnored private var service: AniworldService?
    @ObservationIgnored private var library: LibraryStore?
    @ObservationIgnored private var settings: SettingsStore?
    @ObservationIgnored private weak var coordinator: PlaybackCoordinator?

    @ObservationIgnored private var hosters: [HosterLink] = []
    @ObservationIgnored private var hostersEpisodeID: String?
    @ObservationIgnored private var loadTask: Task<Void, Never>?
    @ObservationIgnored private var countdownTask: Task<Void, Never>?
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var timeObserver: Any?
    @ObservationIgnored private var statusObservation: NSKeyValueObservation?
    @ObservationIgnored private var timeControlObservation: NSKeyValueObservation?
    @ObservationIgnored private var endObserver: NSObjectProtocol?
    @ObservationIgnored private var failObserver: NSObjectProtocol?
    @ObservationIgnored private var triedHosters: Set<String> = []
    @ObservationIgnored private var autoFallbackUsed = false
    @ObservationIgnored private var readyHandled = false
    @ObservationIgnored private var readyForSaving = false
    @ObservationIgnored private var pendingStart: Double = 0
    @ObservationIgnored private var tickCount = 0
    @ObservationIgnored private var nextInfo: (EpisodeRef, [EpisodeRef])?
    @ObservationIgnored private var isShutdown = false
    @ObservationIgnored private var attached = false
    @ObservationIgnored private let initialSession: PlaybackSession

    init(session: PlaybackSession) {
        self.initialSession = session
        self.series = session.series
        self.episode = session.episode
        self.seasonEpisodes = session.seasonEpisodes
        self.currentLanguage = session.language
    }

    var introSkipSeconds: Int { settings?.introSkipSeconds ?? 85 }

    // MARK: Lifecycle

    func attach(service: AniworldService, library: LibraryStore, settings: SettingsStore,
                coordinator: PlaybackCoordinator) {
        guard !attached else { return }
        attached = true
        self.service = service
        self.library = library
        self.settings = settings
        self.coordinator = coordinator

        let interval = CMTime(seconds: 1, preferredTimescale: 600)
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            MainActor.assumeIsolated { self?.tick(time) }
        }
        timeControlObservation = player.observe(\.timeControlStatus, options: [.new]) { [weak self] player, _ in
            let paused = player.timeControlStatus == .paused
            Task { @MainActor in self?.timeControlChanged(paused: paused) }
        }
    }

    func start() {
        configureAudioSession()
        beginLoad(startAt: initialSession.startAt, language: initialSession.language, excluding: [])
    }

    /// Saves progress and releases the player. Idempotent.
    func shutdown() {
        guard !isShutdown else { return }
        saveProgress()
        library?.flush()
        isShutdown = true
        generation += 1
        loadTask?.cancel()
        countdownTask?.cancel()
        removeItemObservers()
        if let timeObserver { player.removeTimeObserver(timeObserver) }
        timeObserver = nil
        timeControlObservation = nil
        player.pause()
        player.replaceCurrentItem(with: nil)
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    func close() {
        shutdown()
        coordinator?.dismiss()
    }

    private func configureAudioSession() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .moviePlayback)
        try? session.setActive(true)
    }

    // MARK: Loading

    private func beginLoad(startAt: Double?, language: StreamLanguage?, excluding: Set<String>) {
        guard !isShutdown else { return }
        loadTask?.cancel()
        countdownTask?.cancel()
        countdown = nil
        generation += 1
        let gen = generation
        player.pause()
        readyForSaving = false
        state = .loading("Lade Hoster…")
        loadTask = Task { [weak self] in
            await self?.runLoad(gen: gen, startAt: startAt, language: language, excluding: excluding)
        }
    }

    private func runLoad(gen: Int, startAt: Double?, language: StreamLanguage?, excluding: Set<String>) async {
        guard let service, let library, let settings else { return }
        do {
            if hostersEpisodeID != episode.id || hosters.isEmpty {
                hosters = []
                let fetched = try await service.hosters(for: episode)
                guard gen == generation else { return }
                hosters = fetched
                hostersEpisodeID = episode.id
            }
            guard !hosters.isEmpty else { throw AniworldError.noPlayableStream }

            let prefs = settings.streamPreferences
            let languages = service.availableLanguages(hosters, preferences: prefs)
            availableLanguages = languages
            var chosen: StreamLanguage?
            for candidate in [language, library.preferredLanguage(seriesSlug: series.slug)] {
                if let c = candidate, languages.contains(c) { chosen = c; break }
            }
            if chosen == nil { chosen = languages.first }
            availableHosters = Self.uniqueNames(hosters.filter { chosen == nil || $0.language == chosen })

            state = .loading(settings.verifyStreams ? "Prüfe Hoster…" : "Löse Stream auf…")
            let stream = try await service.resolveStream(
                hosters: hosters, language: chosen, preferences: prefs,
                verify: settings.verifyStreams, excluding: excluding)
            guard gen == generation else { return }

            let start = startAt ?? savedStartPosition()
            attach(stream: stream, language: stream.language ?? chosen, start: start, gen: gen)
        } catch {
            guard gen == generation, !Task.isCancelled, !(error is CancellationError) else { return }
            if let a = error as? AniworldError, a == .cancelled { return }
            state = .error(Self.message(for: error))
        }
    }

    private static func uniqueNames(_ links: [HosterLink]) -> [String] {
        var seen = Set<String>()
        return links.map(\.name).filter { seen.insert($0).inserted }
    }

    private func savedStartPosition() -> Double {
        guard let p = library?.progress(for: episode), p.duration > 0, !p.watched else { return 0 }
        if p.position > 5 && p.fraction < 0.95 { return p.position }
        return 0
    }

    private func attach(stream: ResolvedStream, language: StreamLanguage?, start: Double, gen: Int) {
        removeItemObservers()
        let asset = AVURLAsset(url: stream.url, options: ["AVURLAssetHTTPHeaderFieldsKey": stream.headers])
        let item = AVPlayerItem(asset: asset)
        item.externalMetadata = metadata()

        readyHandled = false
        pendingStart = start
        currentHoster = stream.hoster
        currentLanguage = language
        position = start
        duration = 0
        tickCount = 0

        statusObservation = item.observe(\.status, options: [.new]) { [weak self] item, _ in
            let status = item.status
            let message = item.error?.localizedDescription
            Task { @MainActor in self?.itemStatusChanged(status, message: message, gen: gen) }
        }
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.itemDidEnd(gen: gen) }
        }
        failObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemFailedToPlayToEndTime, object: item, queue: .main
        ) { [weak self] note in
            let message = (note.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? Error)?.localizedDescription
            MainActor.assumeIsolated { self?.handlePlaybackFailure(message: message, gen: gen) }
        }
        player.replaceCurrentItem(with: item)
        hasItem = true
    }

    private func removeItemObservers() {
        statusObservation = nil
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        if let failObserver { NotificationCenter.default.removeObserver(failObserver) }
        endObserver = nil
        failObserver = nil
    }

    private func metadata() -> [AVMetadataItem] {
        func item(_ id: AVMetadataIdentifier, _ value: String) -> AVMetadataItem {
            let m = AVMutableMetadataItem()
            m.identifier = id
            m.value = value as NSString
            m.extendedLanguageTag = "und"
            return m
        }
        var items = [item(.commonIdentifierTitle, "\(series.title) – \(episode.code)")]
        if !episode.title.isEmpty {
            items.append(item(.iTunesMetadataTrackSubTitle, episode.title))
        }
        return items
    }

    // MARK: Item events

    private func itemStatusChanged(_ status: AVPlayerItem.Status, message: String?, gen: Int) {
        guard gen == generation, !isShutdown else { return }
        switch status {
        case .readyToPlay:
            guard !readyHandled else { return }
            readyHandled = true
            let start = pendingStart
            Task { [weak self] in
                guard let self else { return }
                if start > 0 {
                    let target = CMTime(seconds: start, preferredTimescale: 600)
                    _ = await self.player.seek(to: target, toleranceBefore: .zero, toleranceAfter: .zero)
                }
                guard gen == self.generation, !self.isShutdown else { return }
                if let d = self.player.currentItem?.duration.seconds, d.isFinite, d > 0 { self.duration = d }
                self.state = .playing
                self.readyForSaving = true
                self.player.play()
                Task { await self.prepareNext() }
            }
        case .failed:
            handlePlaybackFailure(message: message, gen: gen)
        default:
            break
        }
    }

    private func handlePlaybackFailure(message: String?, gen: Int) {
        guard gen == generation, !isShutdown else { return }
        let resume = readyForSaving ? currentSeconds() : pendingStart
        if !autoFallbackUsed, let hoster = currentHoster {
            autoFallbackUsed = true
            triedHosters.insert(hoster)
            beginLoad(startAt: resume, language: currentLanguage, excluding: triedHosters)
        } else {
            player.pause()
            state = .error(message.map { "Die Wiedergabe ist fehlgeschlagen: \($0)" }
                           ?? "Die Wiedergabe ist fehlgeschlagen.")
        }
    }

    private func itemDidEnd(gen: Int) {
        guard gen == generation, !isShutdown else { return }
        if duration > 0 { position = duration }
        saveProgress(atEnd: true)
        guard settings?.autoplayNext == true else { return }
        Task { [weak self] in
            guard let self else { return }
            if self.nextInfo == nil { await self.prepareNext() }
            guard gen == self.generation, self.nextInfo != nil else { return }
            self.startCountdown()
        }
    }

    private func timeControlChanged(paused: Bool) {
        guard !isShutdown else { return }
        isPaused = paused
        if paused { saveProgress() }
    }

    private func tick(_ time: CMTime) {
        guard readyForSaving, !isShutdown else { return }
        let s = time.seconds
        if s.isFinite { position = s }
        if let d = player.currentItem?.duration.seconds, d.isFinite, d > 0, d != duration { duration = d }
        tickCount += 1
        if tickCount % 5 == 0 { saveProgress() }
    }

    // MARK: Progress

    private func currentSeconds() -> Double {
        let s = player.currentTime().seconds
        return s.isFinite ? max(s, 0) : position
    }

    func saveProgress(atEnd: Bool = false) {
        guard readyForSaving, let item = player.currentItem, let library else { return }
        let dur = item.duration.seconds
        guard dur.isFinite, dur > 0 else { return }
        var pos = currentSeconds()
        if atEnd { pos = dur }
        library.updateProgress(series: series, episode: episode, language: currentLanguage,
                               position: min(pos, dur), duration: dur)
    }

    // MARK: Next episode & autoplay

    func prepareNext() async {
        guard let coordinator else { return }
        let key = episode.id
        let result = await coordinator.nextEpisode(after: episode, in: series, seasonEpisodes: seasonEpisodes)
        guard key == episode.id, !isShutdown else { return }
        nextInfo = result
        hasNext = result != nil
    }

    private func startCountdown() {
        countdownTask?.cancel()
        countdownTask = Task { [weak self] in
            guard let self else { return }
            var remaining = max(self.settings?.autoplayCountdown ?? 8, 1)
            self.countdown = remaining
            while remaining > 0 {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                if Task.isCancelled { return }
                remaining -= 1
                self.countdown = remaining
            }
            self.countdown = nil
            self.playNext()
        }
    }

    func cancelCountdown() {
        countdownTask?.cancel()
        countdown = nil
    }

    /// Loads the next episode in place (same screen, new item).
    func playNext() {
        guard let (next, episodes) = nextInfo, let library else { return }
        countdownTask?.cancel()
        countdown = nil
        saveProgress()
        library.setWatched(true, episode: episode, series: series)

        episode = next
        seasonEpisodes = episodes
        nextInfo = nil
        hasNext = false
        triedHosters = []
        autoFallbackUsed = false
        position = 0
        duration = 0
        coordinator?.activeSession?.episode = next
        coordinator?.activeSession?.seasonEpisodes = episodes
        beginLoad(startAt: 0, language: currentLanguage, excluding: [])
    }

    // MARK: User actions

    func skipIntro() {
        seek(to: currentSeconds() + Double(introSkipSeconds))
    }

    private func seek(to seconds: Double) {
        var target = seconds
        if duration > 0 { target = min(target, max(duration - 1, 0)) }
        player.seek(to: CMTime(seconds: target, preferredTimescale: 600),
                    toleranceBefore: .zero, toleranceAfter: .zero)
        position = target
    }

    private func resumePosition() -> Double {
        readyForSaving ? currentSeconds() : pendingStart
    }

    func switchLanguage(_ language: StreamLanguage) {
        guard language != currentLanguage else { return }
        saveProgress()
        library?.setPreferredLanguage(language, seriesSlug: series.slug)
        triedHosters = []
        autoFallbackUsed = false
        beginLoad(startAt: resumePosition(), language: language, excluding: [])
    }

    func switchHoster(_ name: String) {
        guard name != currentHoster else { return }
        saveProgress()
        let sameLanguage = hosters.filter { currentLanguage == nil || $0.language == currentLanguage }
        var others = Set(sameLanguage.map(\.name))
        others.remove(name)
        autoFallbackUsed = false
        beginLoad(startAt: resumePosition(), language: currentLanguage, excluding: others)
    }

    func retry() {
        triedHosters = []
        autoFallbackUsed = false
        beginLoad(startAt: resumePosition(), language: currentLanguage, excluding: [])
    }

    func tryOtherHoster() {
        if let currentHoster { triedHosters.insert(currentHoster) }
        autoFallbackUsed = false
        beginLoad(startAt: resumePosition(), language: currentLanguage, excluding: triedHosters)
    }

    // MARK: Errors

    private static func message(for error: Error) -> String {
        if let a = error as? AniworldError {
            switch a {
            case .cloudflareChallenge:
                return "aniworld.to verlangt gerade eine Browser-Prüfung (Cloudflare). Bitte später erneut versuchen."
            case .http(let status, _):
                return "Der Server hat mit einem Fehler geantwortet (HTTP \(status))."
            case .parsing:
                return "Die Seite konnte nicht gelesen werden. Eventuell hat sich aniworld.to geändert."
            case .noPlayableStream:
                return "Kein abspielbarer Stream gefunden. Alle Hoster sind gerade nicht erreichbar."
            case .cancelled:
                return "Abgebrochen."
            }
        }
        if error is URLError {
            return "Keine Verbindung zum Server. Bitte Internetverbindung prüfen."
        }
        return "Unbekannter Fehler: \(error.localizedDescription)"
    }
}
