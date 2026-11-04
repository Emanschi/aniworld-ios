import Foundation
import MediaPlayer
import UIKit

/// Lock screen / Control Center integration (the system player UI did this before).
@MainActor
final class NowPlayingController {
    struct Handlers {
        var play: @MainActor () -> Void
        var pause: @MainActor () -> Void
        var togglePlayPause: @MainActor () -> Void
        /// Relative skip in seconds (negative = backwards).
        var skip: @MainActor (Double) -> Void
        var seek: @MainActor (Double) -> Void
        var next: @MainActor () -> Void
    }

    private let handlers: Handlers
    private var targets: [(MPRemoteCommand, Any)] = []
    private var artworkURL: URL?
    private var artwork: MPMediaItemArtwork?
    private var artworkTask: Task<Void, Never>?
    private var isTornDown = false

    init(handlers: Handlers) {
        self.handlers = handlers
        installCommands()
    }

    private func installCommands() {
        let center = MPRemoteCommandCenter.shared()
        let h = handlers

        func register(_ command: MPRemoteCommand,
                      _ handler: @escaping (MPRemoteCommandEvent) -> MPRemoteCommandHandlerStatus) {
            command.isEnabled = true
            let token = command.addTarget(handler: handler)
            targets.append((command, token))
        }

        register(center.playCommand) { _ in
            Task { @MainActor in h.play() }
            return .success
        }
        register(center.pauseCommand) { _ in
            Task { @MainActor in h.pause() }
            return .success
        }
        register(center.togglePlayPauseCommand) { _ in
            Task { @MainActor in h.togglePlayPause() }
            return .success
        }

        center.skipForwardCommand.preferredIntervals = [10]
        register(center.skipForwardCommand) { event in
            let interval = (event as? MPSkipIntervalCommandEvent)?.interval ?? 10
            Task { @MainActor in h.skip(interval) }
            return .success
        }
        center.skipBackwardCommand.preferredIntervals = [10]
        register(center.skipBackwardCommand) { event in
            let interval = (event as? MPSkipIntervalCommandEvent)?.interval ?? 10
            Task { @MainActor in h.skip(-interval) }
            return .success
        }
        register(center.changePlaybackPositionCommand) { event in
            guard let e = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            let position = e.positionTime
            Task { @MainActor in h.seek(position) }
            return .success
        }
        register(center.nextTrackCommand) { _ in
            Task { @MainActor in h.next() }
            return .success
        }
        center.nextTrackCommand.isEnabled = false
        center.previousTrackCommand.isEnabled = false
    }

    /// Updates the info center. Cheap enough to call about once per second.
    func update(title: String, subtitle: String, duration: Double, elapsed: Double,
                rate: Float, isPlaying: Bool, hasNext: Bool, coverURL: URL?) {
        guard !isTornDown else { return }
        MPRemoteCommandCenter.shared().nextTrackCommand.isEnabled = hasNext

        var info: [String: Any] = [
            MPMediaItemPropertyTitle: title,
            MPMediaItemPropertyArtist: subtitle,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: max(elapsed, 0),
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? Double(rate) : 0.0,
            MPNowPlayingInfoPropertyDefaultPlaybackRate: Double(rate),
        ]
        if duration.isFinite, duration > 0 { info[MPMediaItemPropertyPlaybackDuration] = duration }
        if coverURL != artworkURL {
            artworkURL = coverURL
            artwork = nil
            loadArtwork(coverURL)
        }
        if let artwork { info[MPMediaItemPropertyArtwork] = artwork }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    private func loadArtwork(_ url: URL?) {
        artworkTask?.cancel()
        guard let url else { return }
        artworkTask = Task { [weak self] in
            guard let result = try? await URLSession.shared.data(from: url),
                  !Task.isCancelled, let image = UIImage(data: result.0) else { return }
            let art = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
            guard let self, !self.isTornDown, self.artworkURL == url else { return }
            self.artwork = art
            var info = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
            info[MPMediaItemPropertyArtwork] = art
            MPNowPlayingInfoCenter.default().nowPlayingInfo = info
        }
    }

    func teardown() {
        guard !isTornDown else { return }
        isTornDown = true
        artworkTask?.cancel()
        for (command, token) in targets { command.removeTarget(token) }
        targets = []
        let center = MPRemoteCommandCenter.shared()
        center.skipForwardCommand.preferredIntervals = []
        center.skipBackwardCommand.preferredIntervals = []
        center.nextTrackCommand.isEnabled = false
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    }
}
