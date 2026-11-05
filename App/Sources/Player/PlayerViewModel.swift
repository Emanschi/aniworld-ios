import AVFoundation
import Foundation
import MediaPlayer
import Observation
import AniworldKit

/// Skip button offered by the player (Netflix-style), see `PlayerViewModel.skipPill`.
struct SkipPill: Equatable {
    var title: String
    /// Id of the skip segment; nil for the fixed-jump intro fallback.
    var segmentId: String?
    var isEnding: Bool
}

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
    var skipTimes: [SkipTime] = []
    var activeSkipSegment: SkipTime?
    /// Skip pill that is currently offered (intro, recap, outro or fixed-jump fallback), nil when none.
    private(set) var skipPill: SkipPill?
    /// User-defined times that apply to the current episode (episode entry first, then season entry).
    private(set) var customSkip: CustomSkip?
    /// Shows the small "Kein Intro hinterlegt" card.
    private(set) var noIntroPromptVisible = false

    // Custom-UI state
    var isBuffering = false
    /// End (seconds) of the buffered range containing the current position.
    var bufferedPosition: Double = 0
    /// Playback speed; persists across episodes in this session. Change via `setPlaybackRate(_:)`.
    private(set) var playbackRate: Float = 1.0
    static let playbackRates: [Float] = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0]
    var videoGravity: AVLayerVideoGravity = .resizeAspect
    var isScrubbing = false

    let player = AVPlayer()
    let pip = PictureInPictureController()

    // Internals
    @ObservationIgnored private var service: AniworldService?
    @ObservationIgnored private var library: LibraryStore?
    @ObservationIgnored private var settings: SettingsStore?
    @ObservationIgnored private weak var coordinator: PlaybackCoordinator?
    @ObservationIgnored private var downloads: DownloadManager?
    @ObservationIgnored private var stats: WatchStatsStore?
    @ObservationIgnored private var recorder: WatchSessionRecorder?

    @ObservationIgnored private var hosters: [HosterLink] = []
    @ObservationIgnored private var hostersEpisodeID: String?
    @ObservationIgnored private var loadTask: Task<Void, Never>?
    @ObservationIgnored private var countdownTask: Task<Void, Never>?
    @ObservationIgnored private var skipTimesTask: Task<Void, Never>?
    /// Times from the bundled database for the current episode.
    @ObservationIgnored private var databaseSkipTimes: [SkipTime] = []
    @ObservationIgnored private var skipLookupDone = false
    @ObservationIgnored private var introPromptHandledFor: String?
    @ObservationIgnored private var autoSkippedIds: Set<String> = []
    /// Segments already skipped by the user for `skipStateEpisodeID` (pill stays hidden for them).
    @ObservationIgnored private var skippedSegmentIds: Set<String> = []
    @ObservationIgnored private var fixedIntroSkipUsed = false
    @ObservationIgnored private var skipInFlight = false
    @ObservationIgnored private var skipStateEpisodeID: String?
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
    /// Watched fraction (0...1) of the current episode at the last progress save.
    @ObservationIgnored private var lastWatchedFraction: Double = 0
    private static let watchedThreshold = 0.9
    @ObservationIgnored private var nextInfo: (EpisodeRef, [EpisodeRef])?
    @ObservationIgnored private var isShutdown = false
    @ObservationIgnored private var attached = false
    @ObservationIgnored private var bufferEmptyObservation: NSKeyValueObservation?
    @ObservationIgnored private var nowPlaying: NowPlayingController?
    @ObservationIgnored private var scrubWasPlaying = false
    @ObservationIgnored private var lastScrubSeek = Date.distantPast
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
                coordinator: PlaybackCoordinator, downloads: DownloadManager? = nil,
                stats: WatchStatsStore? = nil) {
        guard !attached else { return }
        attached = true
        self.service = service
        self.library = library
        self.settings = settings
        self.coordinator = coordinator
        self.downloads = downloads
        self.stats = stats
        if let stats { recorder = WatchSessionRecorder(store: stats) }

        player.defaultRate = playbackRate
        pip.onActiveChange = { [weak self] active in self?.isPictureInPictureActive = active }
        nowPlaying = NowPlayingController(handlers: .init(
            play: { [weak self] in self?.play() },
            pause: { [weak self] in self?.pause() },
            togglePlayPause: { [weak self] in self?.togglePlayPause() },
            skip: { [weak self] delta in self?.seek(by: delta) },
            seek: { [weak self] seconds in self?.seek(to: seconds) },
            next: { [weak self] in self?.playNext() }))

        let interval = CMTime(seconds: 0.5, preferredTimescale: 600)
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            MainActor.assumeIsolated { self?.tick(time) }
        }
        timeControlObservation = player.observe(\.timeControlStatus, options: [.new]) { [weak self] player, _ in
            let status = player.timeControlStatus
            Task { @MainActor in self?.timeControlChanged(status: status) }
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
        recorder?.clear()
        isShutdown = true
        generation += 1
        loadTask?.cancel()
        countdownTask?.cancel()
        skipTimesTask?.cancel()
        removeItemObservers()
        if let timeObserver { player.removeTimeObserver(timeObserver) }
        timeObserver = nil
        timeControlObservation = nil
        bufferEmptyObservation = nil
        nowPlaying?.teardown()
        nowPlaying = nil
        pip.stop()
        player.pause()
        player.replaceCurrentItem(with: nil)
        // The file is no longer in use: delete it now if it was watched.
        deleteWatchedDownloadIfNeeded(episodeID: episode.id)
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
        player.allowsExternalPlayback = true
    }

    // MARK: Loading

    private func beginLoad(startAt: Double?, language: StreamLanguage?, excluding: Set<String>) {
        guard !isShutdown else { return }
        loadTask?.cancel()
        countdownTask?.cancel()
        skipTimesTask?.cancel()
        countdown = nil
        skipTimes = []
        databaseSkipTimes = []
        skipLookupDone = false
        customSkip = nil
        noIntroPromptVisible = false
        activeSkipSegment = nil
        autoSkippedIds = []
        recomputeSkipTimes()
        generation += 1
        let gen = generation
        player.pause()
        readyForSaving = false
        state = .loading("Lade Hoster…")
        loadTask = Task { [weak self] in
            await self?.runLoad(gen: gen, startAt: startAt, language: language, excluding: excluding)
        }
    }

    /// Looks up intro/outro times (bundled database, works offline) for the current episode.
    private func loadSkipTimes(service: AniworldService, gen: Int) {
        skipTimesTask = Task { [weak self, series, episode] in
            guard let self else { return }
            var times = await service.skipTimes(
                seriesTitle: series.title,
                seriesSlug: series.slug,
                season: episode.season,
                episode: episode.number
            )
            // AniSkip only when nothing is bundled and the user allows online lookups.
            // Own times still win in `recomputeSkipTimes()`.
            if times.isEmpty, self.settings?.enableSkipDetection == true, self.settings?.onlineSkipTimes == true {
                times = await service.onlineSkipTimes(
                    seriesTitle: series.title,
                    seriesSlug: series.slug,
                    season: episode.season,
                    episode: episode.number
                )
            }
            guard gen == self.generation, !Task.isCancelled else { return }
            self.databaseSkipTimes = times
            self.skipLookupDone = true
            self.recomputeSkipTimes()
            self.evaluateIntroPrompt()
        }
    }

    private func runLoad(gen: Int, startAt: Double?, language: StreamLanguage?, excluding: Set<String>) async {
        guard let service, let library, let settings else { return }
        // Downloaded episodes play from disk, no hoster resolution needed.
        if let local = downloads?.localStream(for: episode) {
            guard gen == generation else { return }
            availableLanguages = []
            availableHosters = []
            loadSkipTimes(service: service, gen: gen)
            attach(stream: local, language: local.language, start: startAt ?? savedStartPosition(), gen: gen,
                   offline: true)
            return
        }
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

            loadSkipTimes(service: service, gen: gen)

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

    private func attach(stream: ResolvedStream, language: StreamLanguage?, start: Double, gen: Int,
                        offline: Bool = false) {
        removeItemObservers()
        recorder?.prepare(WatchSessionRecorder.Context(
            series: series, episode: episode, language: language ?? stream.language,
            hoster: stream.hoster, offline: offline))
        rememberSeriesMeta()
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

        isBuffering = false
        bufferedPosition = 0
        bufferEmptyObservation = item.observe(\.isPlaybackBufferEmpty, options: [.new]) { [weak self] _, _ in
            Task { @MainActor in self?.updateBuffering() }
        }
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
        bufferEmptyObservation = nil
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
                self.evaluateIntroPrompt()
                self.play()
                self.updateNowPlaying()
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
        recorder?.markEnded()
        guard settings?.autoplayNext == true else { return }
        Task { [weak self] in
            guard let self else { return }
            if self.nextInfo == nil { await self.prepareNext() }
            guard gen == self.generation, self.nextInfo != nil, self.countdown == nil else { return }
            self.startCountdown()
        }
    }

    private func timeControlChanged(status: AVPlayer.TimeControlStatus) {
        guard !isShutdown else { return }
        let paused = status == .paused
        if !isScrubbing {
            isPaused = paused
            if paused { saveProgress() }
        }
        updateBuffering()
        updateNowPlaying()
    }

    private func updateBuffering() {
        guard !isShutdown else { return }
        let waiting = player.timeControlStatus == .waitingToPlayAtSpecifiedRate
        let emptyWhilePlaying = (player.currentItem?.isPlaybackBufferEmpty ?? false)
            && !isPaused
        let value = (waiting || emptyWhilePlaying) && state == .playing
        if isBuffering != value { isBuffering = value }
    }

    private func updateBufferedPosition(at now: Double) {
        guard let ranges = player.currentItem?.loadedTimeRanges else { return }
        var end = bufferedPosition
        for value in ranges {
            let r = value.timeRangeValue
            let start = r.start.seconds
            let stop = r.end.seconds
            if start.isFinite, stop.isFinite, now >= start - 0.5, now <= stop + 0.5 {
                end = stop
                break
            }
        }
        if end != bufferedPosition { bufferedPosition = end }
    }

    private func tick(_ time: CMTime) {
        guard readyForSaving, !isShutdown else { return }
        let s = time.seconds
        if s.isFinite, !isScrubbing { position = s }
        if let d = player.currentItem?.duration.seconds, d.isFinite, d > 0, d != duration { duration = d }
        if s.isFinite { updateBufferedPosition(at: s) }
        updateBuffering()

        let currentPos = s.isFinite ? s : position
        recorder?.tick(position: currentPos, duration: duration,
                       isPlaying: player.timeControlStatus == .playing && player.rate > 0,
                       rate: Double(player.rate))
        if skipStateEpisodeID != episode.id {
            skipStateEpisodeID = episode.id
            skippedSegmentIds = []
            fixedIntroSkipUsed = false
            skipInFlight = false
            autoSkippedIds = []
            skipPill = nil
        }
        var active: SkipTime?
        if settings?.enableSkipDetection == true && !skipTimes.isEmpty {
            active = skipTimes.first { seg in
                currentPos >= seg.interval.startTime && currentPos < seg.interval.endTime
            }
        }
        if let current = active, skippedSegmentIds.contains(current.skipId) {
            active = nil
        }
        if activeSkipSegment != active { activeSkipSegment = active }
        if let active {
            let wantsNextOnOutro = active.skipType.isEnding && settings?.autoNextOnOutro == true
                && settings?.autoplayNext == true && hasNext
            let shouldAuto = (active.skipType.isOpening && settings?.autoSkipIntro == true)
                || (active.skipType.isEnding && settings?.autoSkipEnding == true)
                || wantsNextOnOutro
            if shouldAuto && !autoSkippedIds.contains(active.skipId) {
                autoSkippedIds.insert(active.skipId)
                skippedSegmentIds.insert(active.skipId)
                activeSkipSegment = nil
                recorder?.noteSkipped(seconds: skippedAmount(to: active.interval.endTime, from: currentPos))
                if wantsNextOnOutro {
                    if countdown == nil { startCountdown() }
                } else {
                    seek(to: active.interval.endTime)
                }
            }
        }
        updateSkipPill(position: currentPos, active: activeSkipSegment)
        tickCount += 1
        if tickCount % 10 == 0 { saveProgress() }
        if tickCount % 2 == 0 { updateNowPlaying() }
    }

    private func updateNowPlaying() {
        guard !isShutdown, let nowPlaying else { return }
        let subtitle = episode.title.isEmpty ? episode.code : "\(episode.code) – \(episode.title)"
        let playing = player.timeControlStatus != .paused
        nowPlaying.update(title: series.title, subtitle: subtitle, duration: duration,
                          elapsed: position, rate: playbackRate, isPlaying: playing,
                          hasNext: hasNext, coverURL: series.coverURL)
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
        // Only remembered here; a watched download is deleted when the user leaves the episode.
        lastWatchedFraction = min(pos, dur) / dur
    }

    /// Smart Downloads: deletes the download of the episode being left, if it was watched.
    /// Never called while the episode is playing.
    private func deleteWatchedDownloadIfNeeded(episodeID: String) {
        guard settings?.autoDeleteWatchedDownloads == true,
              lastWatchedFraction >= Self.watchedThreshold,
              let downloads, downloads.state(for: episodeID) == .downloaded else { return }
        downloads.delete(episodeID)
    }

    // MARK: Next episode & autoplay

    func prepareNext() async {
        guard let coordinator else { return }
        let key = episode.id
        let result = await coordinator.nextEpisode(after: episode, in: series, seasonEpisodes: seasonEpisodes)
        guard key == episode.id, !isShutdown else { return }
        nextInfo = result
        hasNext = result != nil
        updateNowPlaying()
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
        guard case let (next, episodes)? = nextInfo, let library else { return }
        library.setWatched(true, episode: episode, series: series)
        switchEpisode(to: next, episodes: episodes, startAt: 0)
    }

    var hasPrevious: Bool {
        guard let i = seasonEpisodes.firstIndex(where: { $0.id == episode.id }) else { return false }
        return i > 0
    }

    func playPrevious() {
        guard let i = seasonEpisodes.firstIndex(where: { $0.id == episode.id }), i > 0 else { return }
        playEpisode(seasonEpisodes[i - 1])
    }

    /// Switches to any episode of `seasonEpisodes` in place.
    func playEpisode(_ episode: EpisodeRef) {
        guard episode.id != self.episode.id, seasonEpisodes.contains(where: { $0.id == episode.id }) else { return }
        switchEpisode(to: episode, episodes: seasonEpisodes, startAt: nil)
    }

    private func switchEpisode(to next: EpisodeRef, episodes: [EpisodeRef], startAt: Double?) {
        recorder?.clear()
        countdownTask?.cancel()
        countdown = nil
        saveProgress()
        deleteWatchedDownloadIfNeeded(episodeID: episode.id)
        lastWatchedFraction = 0

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
        beginLoad(startAt: startAt, language: currentLanguage, excluding: [])
    }

    // MARK: User actions

    // MARK: Custom skip times

    /// True when an intro (custom or database) is known for the current episode.
    var hasKnownIntro: Bool {
        settings?.enableSkipDetection == true && skipTimes.contains { $0.skipType.isOpening }
    }

    /// Merges custom and database times: custom intro/outro replace the database ones of the same kind.
    private func recomputeSkipTimes() {
        guard let library else { skipTimes = databaseSkipTimes; return }
        let custom = library.customSkip(seriesSlug: series.slug, season: episode.season, episode: episode.number)
        customSkip = custom
        var result = databaseSkipTimes
        if let custom {
            if custom.hasIntro {
                result.removeAll { $0.skipType.isOpening }
            }
            if custom.hasOutro {
                result.removeAll { $0.skipType.isEnding }
            }
            if custom.hasIntro, let s = custom.introStart, let e = custom.introEnd {
                result.append(SkipTime(skipId: "custom-op", skipType: .op,
                                       interval: SkipInterval(startTime: s, endTime: e),
                                       episodeLength: duration))
            }
            if custom.hasOutro, let s = custom.outroStart, let e = custom.outroEnd {
                result.append(SkipTime(skipId: "custom-ed", skipType: .ed,
                                       interval: SkipInterval(startTime: s, endTime: e),
                                       episodeLength: duration))
            }
        }
        result.sort { $0.interval.startTime < $1.interval.startTime }
        skipTimes = result
    }

    /// Shows the "Kein Intro hinterlegt" card once per episode, if nothing is known.
    private func evaluateIntroPrompt() {
        guard !isShutdown, skipLookupDone, state == .playing,
              introPromptHandledFor != episode.id,
              settings?.enableSkipDetection == true,
              library?.isSkipPromptMuted(seriesSlug: series.slug) == false,
              !hasKnownIntro, position < 300 else { return }
        introPromptHandledFor = episode.id
        noIntroPromptVisible = true
    }

    func dismissIntroPrompt() {
        noIntroPromptVisible = false
    }

    func muteIntroPromptForSeries() {
        library?.muteSkipPrompt(seriesSlug: series.slug)
        noIntroPromptVisible = false
    }

    /// Saves user-defined times. `wholeSeason` stores them for the entire season.
    func saveCustomSkip(wholeSeason: Bool, introStart: Double?, introEnd: Double?,
                        outroStart: Double?, outroEnd: Double?) {
        guard let library else { return }
        if wholeSeason {
            // A season-wide entry must not stay hidden behind an older single-episode entry.
            library.removeCustomSkip(key: CustomSkip.key(seriesSlug: series.slug, season: episode.season,
                                                         episode: episode.number))
        }
        let entry = CustomSkip(seriesSlug: series.slug, season: episode.season,
                               episode: wholeSeason ? nil : episode.number,
                               introStart: introStart, introEnd: introEnd,
                               outroStart: outroStart, outroEnd: outroEnd,
                               updatedAt: Date())
        library.setCustomSkip(entry)
        autoSkippedIds.insert("custom-op")
        autoSkippedIds.insert("custom-ed")
        noIntroPromptVisible = false
        introPromptHandledFor = episode.id
        recomputeSkipTimes()
    }

    /// Deletes the custom entry that currently applies (episode or season).
    func deleteCustomSkip() {
        guard let library, let current = customSkip else { return }
        library.removeCustomSkip(key: current.key)
        recomputeSkipTimes()
    }

    /// Times shown as defaults in the editor: custom entry, else the database intro.
    var editorDefaults: (introStart: Double?, introEnd: Double?, outroStart: Double?, outroEnd: Double?) {
        if let custom = customSkip {
            return (custom.introStart, custom.introEnd, custom.outroStart, custom.outroEnd)
        }
        let op = skipTimes.first { $0.skipType.isOpening }
        let ed = skipTimes.first { $0.skipType.isEnding }
        return (op?.interval.startTime, op?.interval.endTime, ed?.interval.startTime, ed?.interval.endTime)
    }

    /// Recomputes the pill; only assigns on change so observers are not invalidated every tick.
    private func updateSkipPill(position pos: Double, active: SkipTime?) {
        var pill: SkipPill?
        if skipInFlight || countdown != nil {
            pill = nil
        } else if let active {
            pill = SkipPill(title: active.skipType.buttonTitle, segmentId: active.skipId,
                            isEnding: active.skipType.isEnding)
        } else if !fixedIntroSkipUsed && !hasKnownIntro && pos < 240
                    && duration > Double(introSkipSeconds) + 120 {
            pill = SkipPill(title: "Intro überspringen", segmentId: nil, isEnding: false)
        }
        if pill != skipPill { skipPill = pill }
    }

    /// Called by the skip pill. Ignored while a skip is running; each segment can be skipped once.
    func skipActiveOrIntro() {
        guard !skipInFlight, let pill = skipPill else { return }
        skipInFlight = true
        skipPill = nil
        if let id = pill.segmentId {
            skippedSegmentIds.insert(id)
            autoSkippedIds.insert(id)
            let target = activeSkipSegment?.skipId == id ? activeSkipSegment?.interval.endTime : nil
            if let target { recorder?.noteSkipped(seconds: skippedAmount(to: target, from: currentSeconds())) }
            activeSkipSegment = nil
            if pill.isEnding && settings?.autoplayNext == true && hasNext {
                // Outro skip goes straight to the next episode (countdown card).
                skipInFlight = false
                if countdown == nil { startCountdown() }
                return
            }
            if let target {
                seek(to: target) { [weak self] in self?.skipInFlight = false }
                return
            }
            skipInFlight = false
        } else {
            fixedIntroSkipUsed = true
            recorder?.noteSkipped(seconds: Double(introSkipSeconds))
            seek(to: currentSeconds() + Double(introSkipSeconds)) { [weak self] in self?.skipInFlight = false }
        }
    }

    func skipIntro() {
        recorder?.noteSkipped(seconds: Double(introSkipSeconds))
        seek(to: currentSeconds() + Double(introSkipSeconds))
    }

    private func skippedAmount(to target: Double, from current: Double) -> Double {
        let limit = duration > 0 ? min(target, duration) : target
        return max(limit - current, 0)
    }

    // MARK: Statistics

    /// Ends the running watch session (app in the background) and writes the statistics to disk.
    func flushStats() {
        recorder?.finish()
        stats?.flush()
    }

    /// Remembers genres / age rating of the series once, so the statistics can show favourite genres.
    private func rememberSeriesMeta() {
        guard let stats, let service, !stats.hasMeta(forSlug: series.slug) else { return }
        let slug = series.slug
        Task { [weak stats] in
            if let detail = try? await service.seriesDetail(slug: slug) {
                stats?.noteSeries(detail)
            }
        }
    }

    private func clamped(_ seconds: Double) -> Double {
        var target = max(seconds, 0)
        if duration > 0 { target = min(target, max(duration - 1, 0)) }
        return target
    }

    func seek(by seconds: Double) {
        seek(to: (isScrubbing ? position : currentSeconds()) + seconds)
    }

    /// Accurate seek; the displayed position updates immediately.
    func seek(to seconds: Double, completion: (@MainActor () -> Void)? = nil) {
        let target = clamped(seconds)
        position = target
        player.seek(to: CMTime(seconds: target, preferredTimescale: 600),
                    toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] _ in
            Task { @MainActor in
                self?.updateNowPlaying()
                completion?()
            }
        }
    }

    // MARK: Playback control

    func play() {
        guard !isShutdown else { return }
        player.defaultRate = playbackRate
        player.play()
    }

    func pause() {
        player.pause()
    }

    func togglePlayPause() {
        if player.timeControlStatus == .paused { play() } else { pause() }
    }

    func setPlaybackRate(_ rate: Float) {
        playbackRate = rate
        player.defaultRate = rate
        if player.timeControlStatus != .paused { player.rate = rate }
        updateNowPlaying()
    }

    func toggleVideoGravity() {
        videoGravity = videoGravity == .resizeAspect ? .resizeAspectFill : .resizeAspect
    }

    func attachLayer(_ layer: AVPlayerLayer) {
        pip.attach(to: layer)
        isPictureInPictureActive = pip.isActive
    }

    // MARK: Scrubbing

    func beginScrubbing() {
        guard !isScrubbing else { return }
        scrubWasPlaying = player.timeControlStatus != .paused
        isScrubbing = true
        player.pause()
    }

    /// Updates the displayed position; real seeks are throttled with a tolerance.
    func scrub(to seconds: Double) {
        if !isScrubbing { beginScrubbing() }
        let target = clamped(seconds)
        position = target
        let now = Date()
        guard now.timeIntervalSince(lastScrubSeek) >= 0.15 else { return }
        lastScrubSeek = now
        let tolerance = CMTime(seconds: 1, preferredTimescale: 600)
        player.seek(to: CMTime(seconds: target, preferredTimescale: 600),
                    toleranceBefore: tolerance, toleranceAfter: tolerance)
    }

    func endScrubbing(at seconds: Double) {
        let target = clamped(seconds)
        position = target
        let resume = scrubWasPlaying
        scrubWasPlaying = false
        player.seek(to: CMTime(seconds: target, preferredTimescale: 600),
                    toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.isScrubbing = false
                self.isPaused = self.player.timeControlStatus == .paused
                if resume { self.play() }
                self.updateNowPlaying()
            }
        }
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
