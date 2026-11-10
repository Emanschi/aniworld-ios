import AVFoundation
import Foundation
import Observation
import AniworldKit

/// Casting session of one player: finds Chromecast-compatible receivers (Chromecast, Google TV,
/// Fire TV with a Cast receiver app), hands them the current stream through `CastStreamProxy`
/// and mirrors the receiver's playback state for the player UI.
@MainActor
@Observable
final class CastController {
    enum Phase: Equatable {
        case idle
        case connecting
        case active
        case failed(String)
    }

    let discovery = CastDiscovery()
    private(set) var phase: Phase = .idle
    private(set) var device: CastDiscovery.Device?
    /// Receiver position/duration from the last media status.
    private(set) var position: Double = 0
    private(set) var duration: Double?
    private(set) var isPaused = false
    private(set) var isBuffering = false
    /// TV volume 0...1 (last RECEIVER_STATUS or what the user set).
    private(set) var volume: Double = 0
    /// True once the receiver reported its volume.
    private(set) var hasVolume = false
    /// Our own web receiver is running (skip / next-up / toast messages reach the TV).
    private(set) var usesCustomReceiver = false
    /// Short hint for the user, e.g. the fallback to the standard receiver. Cleared by the UI.
    private(set) var notice: String?
    /// Last time the app itself changed the volume; hardware-button echoes are ignored shortly after.
    @ObservationIgnored private(set) var lastVolumeSetAt = Date.distantPast
    @ObservationIgnored private var lastVolumeSent = Date.distantPast

    /// Called with the receiver's media status (already reflected in the properties above).
    @ObservationIgnored var onStatus: ((CastClient.MediaStatus) -> Void)?
    /// The episode played to its end on the receiver.
    @ObservationIgnored var onFinished: (() -> Void)?
    /// Casting ended (user stopped it, connection lost); passes the last known position.
    @ObservationIgnored var onEnded: ((Double) -> Void)?

    @ObservationIgnored private var client: CastClient?
    @ObservationIgnored private let keepAlive = SilentAudioKeepAlive()
    @ObservationIgnored private var mediaLoaded = false
    @ObservationIgnored private var pendingVolumeTask: Task<Void, Never>?

    /// True from choosing a device until casting ends.
    var isActive: Bool {
        switch phase {
        case .connecting, .active: return true
        case .idle, .failed: return false
        }
    }

    var deviceName: String { device?.name ?? "Fernseher" }

    // MARK: Session

    /// Connects to `device` and plays `stream` there from `startTime`.
    func begin(device: CastDiscovery.Device, stream: ResolvedStream, title: String, subtitle: String?,
               imageURL: URL?, startTime: Double, receiverAppID: String) {
        end(notify: false)
        self.device = device
        phase = .connecting
        position = startTime
        duration = nil
        isPaused = false
        isBuffering = true
        mediaLoaded = false
        hasVolume = false
        usesCustomReceiver = false
        notice = nil

        let client = CastClient(device: device, appID: receiverAppID)
        client.onStateChange = { [weak self] state in self?.clientStateChanged(state) }
        client.onMediaStatus = { [weak self] status in self?.mediaStatusChanged(status) }
        client.onNotice = { [weak self] text in self?.notice = text }
        client.onVolume = { [weak self] level, _ in self?.receiverVolumeChanged(level) }
        client.onControlChannel = { [weak self] available in self?.usesCustomReceiver = available }
        self.client = client
        client.connect()
        keepAlive.start()
        load(stream: stream, title: title, subtitle: subtitle, imageURL: imageURL, startTime: startTime)
    }

    /// Sends another stream (e.g. the next episode) to the connected receiver.
    func load(stream: ResolvedStream, title: String, subtitle: String?, imageURL: URL?, startTime: Double) {
        guard let client else { return }
        do {
            try CastStreamProxy.shared.start()
        } catch {
            fail("Der Stream konnte nicht im WLAN bereitgestellt werden.")
            return
        }
        guard let url = CastStreamProxy.shared.publicURL(for: stream.url, headers: stream.headers) else {
            if stream.url.isFileURL && stream.url.pathExtension.lowercased() == "movpkg" {
                // AVFoundation's HLS download packages are not plain files a receiver could read.
                fail("Diese heruntergeladene Folge lässt sich nicht streamen. Lösch den Download, um sie online zu streamen.")
            } else {
                fail("Kein WLAN gefunden. iPhone und Fernseher müssen im selben WLAN sein.")
            }
            return
        }
        mediaLoaded = false
        isBuffering = true
        position = startTime
        client.load(url: url, contentType: CastStreamProxy.contentType(for: stream.url), title: title,
                    subtitle: subtitle, imageURL: imageURL, startTime: startTime, autoplay: true)
    }

    /// Stops playback on the receiver and ends the session.
    func stop() {
        client?.stop()
        end(notify: true)
    }

    func play() {
        isPaused = false
        client?.play()
    }

    func pause() {
        isPaused = true
        client?.pause()
    }

    func togglePlayPause() {
        if isPaused { play() } else { pause() }
    }

    func seek(to seconds: Double) {
        position = max(seconds, 0)
        isBuffering = true
        client?.seek(to: position)
    }

    // MARK: Volume & TV messages

    /// Sets the TV volume. `mirrorToPhone` moves the iPhone's volume slider along, so the hardware
    /// buttons continue from the same level.
    func setVolume(_ level: Double, mirrorToPhone: Bool) {
        let clamped = min(max(level, 0), 1)
        volume = clamped
        lastVolumeSetAt = Date()
        if mirrorToPhone { VolumeController.shared.setVolume(Float(clamped)) }
        // Sliders deliver many values: send at most about 10 per second, the last one always wins.
        let now = Date()
        if now.timeIntervalSince(lastVolumeSent) >= 0.1 {
            lastVolumeSent = now
            client?.setVolume(clamped)
        } else {
            pendingVolumeTask?.cancel()
            pendingVolumeTask = Task { [weak self] in
                try? await Task.sleep(nanoseconds: 120_000_000)
                if Task.isCancelled { return }
                guard let self else { return }
                self.lastVolumeSent = Date()
                self.client?.setVolume(self.volume)
            }
        }
    }

    func clearNotice() {
        notice = nil
    }

    /// Tells our web receiver that a segment was skipped (shows a short hint on the TV).
    func sendSkip(to seconds: Double, label: String) {
        client?.sendControl(["type": "skip", "to": seconds, "label": label])
    }

    /// Announces the next episode on the TV a few seconds before the end.
    func sendNextUp(title: String, seconds: Int) {
        client?.sendControl(["type": "nextUp", "title": title, "seconds": seconds])
    }

    func sendToast(_ text: String) {
        client?.sendControl(["type": "toast", "text": text])
    }

    private func receiverVolumeChanged(_ level: Double) {
        let first = !hasVolume
        hasVolume = true
        // Right after the user's own change the receiver may still report the old value.
        if Date().timeIntervalSince(lastVolumeSetAt) > 1.0 { volume = level }
        if first {
            // Hardware buttons should start from the TV's level.
            lastVolumeSetAt = Date()
            volume = level
            VolumeController.shared.setVolume(Float(level))
        }
    }

    // MARK: Events

    private func clientStateChanged(_ state: CastClient.State) {
        switch state {
        case .failed(let message):
            fail(message.isEmpty ? "Die Verbindung zum Fernseher ist abgebrochen." : message)
        case .idle:
            if isActive { end(notify: true) }
        case .connecting, .connected:
            break
        }
    }

    private func mediaStatusChanged(_ status: CastClient.MediaStatus) {
        guard isActive else { return }
        // An IDLE status before the media loaded reports 0 s; keep the start position then.
        if status.playerState != "IDLE" { position = status.currentTime }
        if let d = status.duration, d.isFinite, d > 0 { duration = d }
        switch status.playerState {
        case "PLAYING":
            phase = .active
            mediaLoaded = true
            isPaused = false
            isBuffering = false
        case "PAUSED":
            phase = .active
            mediaLoaded = true
            isPaused = true
            isBuffering = false
        case "BUFFERING":
            isBuffering = true
        default:
            // IDLE: finished, failed or replaced by another sender.
            isBuffering = false
            switch status.idleReason {
            case "FINISHED":
                onStatus?(status)
                onFinished?()
                return
            case "ERROR":
                fail("Der Fernseher konnte diesen Stream nicht abspielen. Versuch einen anderen Hoster.")
                return
            case "CANCELLED", "INTERRUPTED":
                if mediaLoaded { end(notify: true); return }
            default:
                break
            }
        }
        onStatus?(status)
    }

    private func fail(_ message: String) {
        let last = position
        teardown()
        phase = .failed(message)
        onEnded?(last)
    }

    /// Clears a shown error.
    func dismissError() {
        if case .failed = phase { phase = .idle }
    }

    private func end(notify: Bool) {
        let wasActive = isActive
        let last = position
        teardown()
        phase = .idle
        if notify && wasActive { onEnded?(last) }
    }

    private func teardown() {
        client?.onStateChange = nil
        client?.onMediaStatus = nil
        client?.onNotice = nil
        client?.onVolume = nil
        client?.onControlChannel = nil
        client?.disconnect()
        client = nil
        keepAlive.stop()
        pendingVolumeTask?.cancel()
        pendingVolumeTask = nil
        usesCustomReceiver = false
        hasVolume = false
        isBuffering = false
        mediaLoaded = false
    }

    /// Player closes: stops the receiver as well.
    func shutdown() {
        if isActive { client?.stop() }
        onEnded = nil
        onFinished = nil
        onStatus = nil
        teardown()
        phase = .idle
        discovery.stop()
    }
}

/// Plays inaudible audio in a loop while casting so iOS keeps the app (and the stream proxy)
/// running when the screen is locked; the background mode "audio" is already enabled.
@MainActor
final class SilentAudioKeepAlive {
    private var player: AVAudioPlayer?

    func start() {
        guard player == nil else { return }
        guard let p = try? AVAudioPlayer(data: Self.silentWAV()) else { return }
        p.numberOfLoops = -1
        p.volume = 0
        p.prepareToPlay()
        p.play()
        player = p
    }

    func stop() {
        player?.stop()
        player = nil
    }

    /// One second of 16-bit mono silence at 8 kHz as a WAV file.
    private static func silentWAV() -> Data {
        let sampleRate: UInt32 = 8000
        let samples = Data(count: Int(sampleRate) * 2)
        var data = Data()
        func append(_ string: String) { data.append(contentsOf: Array(string.utf8)) }
        func append32(_ value: UInt32) { withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) } }
        func append16(_ value: UInt16) { withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) } }
        append("RIFF")
        append32(UInt32(36 + samples.count))
        append("WAVE")
        append("fmt ")
        append32(16)
        append16(1)              // PCM
        append16(1)              // mono
        append32(sampleRate)
        append32(sampleRate * 2) // byte rate
        append16(2)              // block align
        append16(16)             // bits per sample
        append("data")
        append32(UInt32(samples.count))
        data.append(samples)
        return data
    }
}
