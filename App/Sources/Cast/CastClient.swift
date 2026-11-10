import Foundation
import Network
import Security

// MARK: - Protobuf codec (CastMessage)

/// The CASTV2 `CastMessage` protobuf, hand-encoded so no protobuf library is needed.
/// Only string payloads are used; binary payloads (field 7) are skipped when decoding.
private struct CastMessage {
    var sourceID: String
    var destinationID: String
    var namespace: String
    var payload: String

    /// Serializes the message including the 4-byte big-endian length prefix.
    func framed() -> Data {
        var body: [UInt8] = []
        // 1: protocol_version = CASTV2_1_0 (0)
        CastMessage.appendTag(field: 1, wireType: 0, to: &body)
        CastMessage.appendVarint(0, to: &body)
        // 2..4: source, destination, namespace
        CastMessage.appendString(field: 2, sourceID, to: &body)
        CastMessage.appendString(field: 3, destinationID, to: &body)
        CastMessage.appendString(field: 4, namespace, to: &body)
        // 5: payload_type = STRING (0)
        CastMessage.appendTag(field: 5, wireType: 0, to: &body)
        CastMessage.appendVarint(0, to: &body)
        // 6: payload_utf8
        CastMessage.appendString(field: 6, payload, to: &body)

        let length = UInt32(body.count)
        var frame: [UInt8] = [
            UInt8((length >> 24) & 0xFF),
            UInt8((length >> 16) & 0xFF),
            UInt8((length >> 8) & 0xFF),
            UInt8(length & 0xFF)
        ]
        frame.append(contentsOf: body)
        return Data(frame)
    }

    /// Decodes a message body (without the length prefix). Returns nil for malformed input.
    static func decode(_ bytes: [UInt8]) -> CastMessage? {
        var message = CastMessage(sourceID: "", destinationID: "", namespace: "", payload: "")
        var index = 0
        while index < bytes.count {
            guard let tag = readVarint(bytes, &index) else { return nil }
            let field = Int(tag >> 3)
            let wireType = Int(tag & 0x7)
            switch wireType {
            case 0:
                guard readVarint(bytes, &index) != nil else { return nil }
            case 1:
                guard index + 8 <= bytes.count else { return nil }
                index += 8
            case 2:
                guard let rawLength = readVarint(bytes, &index),
                      rawLength <= UInt64(bytes.count - index) else { return nil }
                let length = Int(rawLength)
                let slice = bytes[index..<(index + length)]
                index += length
                let text = String(decoding: slice, as: UTF8.self)
                switch field {
                case 2: message.sourceID = text
                case 3: message.destinationID = text
                case 4: message.namespace = text
                case 6: message.payload = text
                default: break // 7 = payload_binary and unknown fields are ignored
                }
            case 5:
                guard index + 4 <= bytes.count else { return nil }
                index += 4
            default:
                return nil
            }
        }
        return message
    }

    private static func appendVarint(_ value: UInt64, to out: inout [UInt8]) {
        var v = value
        while v >= 0x80 {
            out.append(UInt8(v & 0x7F) | 0x80)
            v >>= 7
        }
        out.append(UInt8(v))
    }

    private static func appendTag(field: Int, wireType: Int, to out: inout [UInt8]) {
        appendVarint(UInt64((field << 3) | wireType), to: &out)
    }

    private static func appendString(field: Int, _ value: String, to out: inout [UInt8]) {
        let utf8 = Array(value.utf8)
        appendTag(field: field, wireType: 2, to: &out)
        appendVarint(UInt64(utf8.count), to: &out)
        out.append(contentsOf: utf8)
    }

    private static func readVarint(_ bytes: [UInt8], _ index: inout Int) -> UInt64? {
        var result: UInt64 = 0
        var shift: UInt64 = 0
        while index < bytes.count, shift < 64 {
            let byte = bytes[index]
            index += 1
            result |= UInt64(byte & 0x7F) << shift
            if byte & 0x80 == 0 { return result }
            shift += 7
        }
        return nil
    }
}

// MARK: - Client

/// Minimal Google Cast (CASTV2) sender. Launches the configured custom receiver app (see
/// `receiver/` in the repo) and falls back to the Default Media Receiver if that is not available.
/// All callbacks and state changes happen on the main actor.
@MainActor
final class CastClient {
    enum State: Equatable {
        case idle
        case connecting
        case connected
        case failed(String)
    }

    struct MediaStatus: Equatable {
        /// "IDLE", "PLAYING", "PAUSED" or "BUFFERING".
        var playerState: String
        var currentTime: Double
        var duration: Double?
        /// "FINISHED", "ERROR", "CANCELLED" or "INTERRUPTED" (only while IDLE).
        var idleReason: String?
    }

    private(set) var state: State = .idle
    var onStateChange: ((State) -> Void)?
    var onMediaStatus: ((MediaStatus) -> Void)?
    /// Short user-facing notice (e.g. the fallback to the standard receiver).
    var onNotice: ((String) -> Void)?
    /// TV volume (0...1) and mute state from RECEIVER_STATUS.
    var onVolume: ((Double, Bool) -> Void)?
    /// Called when the running receiver app (un)registers the app's control namespace.
    var onControlChannel: ((Bool) -> Void)?
    let device: CastDiscovery.Device

    // Protocol constants
    private static let senderID = "sender-0"
    private static let receiverID = "receiver-0"
    static let defaultMediaReceiverAppID = "CC1AD845"
    /// Custom namespace of our own web receiver (skip / next-up / toast messages).
    static let controlNS = "urn:x-cast:com.aniworldios.control"
    private static let connectionNS = "urn:x-cast:com.google.cast.tp.connection"
    private static let heartbeatNS = "urn:x-cast:com.google.cast.tp.heartbeat"
    private static let receiverNS = "urn:x-cast:com.google.cast.receiver"
    private static let mediaNS = "urn:x-cast:com.google.cast.media"
    private static let pingInterval = 5
    private static let heartbeatTimeout: TimeInterval = 20
    private static let maxFrameSize = 8 * 1024 * 1024

    private struct PendingLoad {
        var url: URL
        var contentType: String
        var title: String
        var subtitle: String?
        var imageURL: URL?
        var startTime: Double
        var autoplay: Bool
    }

    private var connection: NWConnection?
    private var receiveBuffer: [UInt8] = []
    private var requestCounter = 0
    private var tickTimer: Timer?
    private var tickCount = 0
    private var lastReceived = Date()

    private var transportID: String?
    private var sessionID: String?
    private var mediaSessionID: Int?
    private var lastDuration: Double?
    private var pendingLoad: PendingLoad?
    /// App id that is (or is about to be) launched on the receiver.
    private var launchedAppID: String
    private var supportsControlChannel = false

    /// - Parameter appID: custom receiver app id; empty means the Default Media Receiver.
    init(device: CastDiscovery.Device, appID: String) {
        self.device = device
        let trimmed = appID.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        self.launchedAppID = trimmed.isEmpty ? CastClient.defaultMediaReceiverAppID : trimmed
    }

    /// True while our own web receiver (with the control namespace) is running.
    var hasControlChannel: Bool { supportsControlChannel }

    // MARK: Public API

    func connect() {
        switch state {
        case .connecting, .connected:
            return
        case .idle, .failed:
            break
        }
        resetSession()
        setState(.connecting)

        let tls = NWProtocolTLS.Options()
        // Cast receivers present self-signed certificates, so every certificate is accepted.
        sec_protocol_options_set_verify_block(
            tls.securityProtocolOptions,
            { _, _, complete in complete(true) },
            DispatchQueue.main
        )
        let parameters = NWParameters(tls: tls, tcp: NWProtocolTCP.Options())
        parameters.includePeerToPeer = false

        let conn = NWConnection(to: device.endpoint, using: parameters)
        connection = conn
        conn.stateUpdateHandler = { [weak self, weak conn] newState in
            MainActor.assumeIsolated {
                guard let self, let conn, self.connection === conn else { return }
                self.handleConnectionState(newState)
            }
        }
        // The main queue lets the handlers use MainActor.assumeIsolated.
        conn.start(queue: .main)
        // `.waiting` is not fatal (e.g. while iOS asks for local network access), so give up only
        // if the socket is still not ready after a while.
        DispatchQueue.main.asyncAfter(deadline: .now() + 20) { [weak self, weak conn] in
            MainActor.assumeIsolated {
                guard let self, let conn, self.connection === conn, self.state == .connecting else { return }
                self.fail("Gerät nicht erreichbar. Ist es im selben WLAN?")
            }
        }
    }

    func load(
        url: URL,
        contentType: String,
        title: String,
        subtitle: String?,
        imageURL: URL?,
        startTime: Double,
        autoplay: Bool
    ) {
        let request = PendingLoad(
            url: url,
            contentType: contentType,
            title: title,
            subtitle: subtitle,
            imageURL: imageURL,
            startTime: startTime,
            autoplay: autoplay
        )
        if state == .connected, transportID != nil {
            sendLoad(request)
        } else {
            // Receiver app is not ready yet: sent as soon as the transport is connected.
            pendingLoad = request
        }
    }

    func play() {
        sendMediaCommand("PLAY", extra: [:])
    }

    func pause() {
        sendMediaCommand("PAUSE", extra: [:])
    }

    func seek(to seconds: Double) {
        sendMediaCommand("SEEK", extra: ["currentTime": max(0, seconds)])
    }

    /// Sets the TV volume (0...1).
    func setVolume(_ level: Double) {
        guard state == .connected else { return }
        send(
            namespace: Self.receiverNS,
            destination: Self.receiverID,
            payload: [
                "type": "SET_VOLUME",
                "volume": ["level": min(max(level, 0), 1)],
                "requestId": nextRequestID()
            ]
        )
    }

    /// Sends a message to the custom web receiver; ignored with the standard receiver.
    func sendControl(_ payload: [String: Any]) {
        guard state == .connected, supportsControlChannel, let transportID else { return }
        send(namespace: Self.controlNS, destination: transportID, payload: payload)
    }

    /// Stops the media and closes the receiver app.
    func stop() {
        pendingLoad = nil
        sendMediaCommand("STOP", extra: [:])
        if let sessionID {
            send(
                namespace: Self.receiverNS,
                destination: Self.receiverID,
                payload: ["type": "STOP", "sessionId": sessionID, "requestId": nextRequestID()]
            )
        }
        mediaSessionID = nil
    }

    func disconnect() {
        let conn = connection
        connection = nil
        stopTimer()

        if let conn, state == .connected {
            // Best effort: tell the receiver we are leaving, then close the socket.
            var data = Data()
            if let transportID {
                data.append(frame(Self.connectionNS, transportID, ["type": "CLOSE"]))
            }
            data.append(frame(Self.connectionNS, Self.receiverID, ["type": "CLOSE"]))
            conn.send(content: data, completion: .contentProcessed { _ in conn.cancel() })
        } else {
            conn?.cancel()
        }
        resetSession()
        setState(.idle)
    }

    // MARK: Connection handling

    private func handleConnectionState(_ newState: NWConnection.State) {
        switch newState {
        case .ready:
            guard state == .connecting else { return }
            lastReceived = Date()
            send(namespace: Self.connectionNS, destination: Self.receiverID, payload: ["type": "CONNECT"])
            setState(.connected)
            startTimer()
            if let conn = connection { receiveLoop(conn) }
            launchReceiverApp()
        case .waiting:
            break // retried by Network.framework; the timeout in connect() ends it
        case .failed(let error):
            fail("Verbindung fehlgeschlagen (\(error.localizedDescription))")
        case .setup, .preparing, .cancelled:
            break
        @unknown default:
            break
        }
    }

    /// Launches (or re-attaches to) the receiver app `launchedAppID`.
    private func launchReceiverApp() {
        send(
            namespace: Self.receiverNS,
            destination: Self.receiverID,
            payload: [
                "type": "LAUNCH",
                "appId": launchedAppID,
                "requestId": nextRequestID()
            ]
        )
    }

    private func receiveLoop(_ conn: NWConnection) {
        conn.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self, weak conn] data, _, isComplete, error in
            MainActor.assumeIsolated {
                guard let self, let conn, self.connection === conn else { return }
                if let data, !data.isEmpty {
                    self.lastReceived = Date()
                    self.receiveBuffer.append(contentsOf: data)
                    self.drainBuffer()
                    guard self.connection === conn else { return } // a handler may have failed
                }
                if let error {
                    self.fail("Verbindung unterbrochen (\(error.localizedDescription))")
                } else if isComplete {
                    self.fail("Verbindung vom Gerät geschlossen")
                } else {
                    self.receiveLoop(conn)
                }
            }
        }
    }

    /// Extracts every complete frame from the buffer; partial frames stay buffered.
    private func drainBuffer() {
        while receiveBuffer.count >= 4 {
            let length = (Int(receiveBuffer[0]) << 24) | (Int(receiveBuffer[1]) << 16)
                | (Int(receiveBuffer[2]) << 8) | Int(receiveBuffer[3])
            if length > Self.maxFrameSize {
                fail("Ungültige Antwort vom Gerät")
                return
            }
            guard receiveBuffer.count >= 4 + length else { return }
            let body = Array(receiveBuffer[4..<(4 + length)])
            receiveBuffer.removeFirst(4 + length)
            if let message = CastMessage.decode(body) {
                handle(message)
            }
            if connection == nil { return }
        }
    }

    private func fail(_ message: String) {
        guard state == .connecting || state == .connected else { return }
        let conn = connection
        connection = nil
        conn?.cancel()
        stopTimer()
        resetSession()
        setState(.failed(message))
    }

    private func resetSession() {
        receiveBuffer.removeAll()
        transportID = nil
        sessionID = nil
        mediaSessionID = nil
        lastDuration = nil
        pendingLoad = nil
        setControlChannel(false)
    }

    private func setControlChannel(_ available: Bool) {
        guard supportsControlChannel != available else { return }
        supportsControlChannel = available
        onControlChannel?(available)
    }

    private func setState(_ newState: State) {
        guard state != newState else { return }
        state = newState
        onStateChange?(newState)
    }

    // MARK: Timer (heartbeat + status polling)

    private func startTimer() {
        stopTimer()
        tickCount = 0
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        tickTimer = timer
    }

    private func stopTimer() {
        tickTimer?.invalidate()
        tickTimer = nil
    }

    private func tick() {
        guard state == .connected else { return }
        if Date().timeIntervalSince(lastReceived) > Self.heartbeatTimeout {
            fail("Gerät antwortet nicht mehr")
            return
        }
        tickCount += 1
        if tickCount % Self.pingInterval == 0 {
            send(namespace: Self.heartbeatNS, destination: Self.receiverID, payload: ["type": "PING"])
        }
        if let transportID, mediaSessionID != nil {
            send(
                namespace: Self.mediaNS,
                destination: transportID,
                payload: ["type": "GET_STATUS", "requestId": nextRequestID()]
            )
        }
    }

    // MARK: Incoming messages

    private func handle(_ message: CastMessage) {
        guard let json = parseJSON(message.payload) else { return }
        let type = json["type"] as? String ?? ""

        switch message.namespace {
        case Self.heartbeatNS:
            if type == "PING" {
                send(namespace: Self.heartbeatNS, destination: message.sourceID, payload: ["type": "PONG"])
            }
        case Self.connectionNS:
            if type == "CLOSE" {
                fail("Gerät hat die Verbindung beendet")
            }
        case Self.receiverNS:
            handleReceiver(type: type, json: json)
        case Self.mediaNS:
            handleMedia(type: type, json: json)
        default:
            break
        }
    }

    private func handleReceiver(type: String, json: [String: Any]) {
        switch type {
        case "RECEIVER_STATUS":
            let status = json["status"] as? [String: Any]
            let apps = status?["applications"] as? [[String: Any]] ?? []
            if let volume = status?["volume"] as? [String: Any],
               let level = (volume["level"] as? NSNumber)?.doubleValue {
                onVolume?(min(max(level, 0), 1), (volume["muted"] as? Bool) ?? false)
            }
            let app = apps.first { ($0["appId"] as? String)?.uppercased() == launchedAppID }
            guard let app,
                  let transport = app["transportId"] as? String,
                  let session = app["sessionId"] as? String else {
                if transportID != nil {
                    // The receiver app was closed (stop, remote control, other sender).
                    transportID = nil
                    sessionID = nil
                    mediaSessionID = nil
                    setControlChannel(false)
                    onMediaStatus?(MediaStatus(
                        playerState: "IDLE",
                        currentTime: 0,
                        duration: lastDuration,
                        idleReason: "CANCELLED"
                    ))
                }
                return
            }
            let namespaces = (app["namespaces"] as? [[String: Any]] ?? []).compactMap { $0["name"] as? String }
            setControlChannel(namespaces.contains(Self.controlNS))
            sessionID = session
            if transportID != transport {
                transportID = transport
                mediaSessionID = nil
                send(namespace: Self.connectionNS, destination: transport, payload: ["type": "CONNECT"])
                if let pending = pendingLoad {
                    pendingLoad = nil
                    sendLoad(pending)
                }
            }
        case "LAUNCH_ERROR":
            if launchedAppID != Self.defaultMediaReceiverAppID {
                // Custom receiver unknown, not published or not allowed on this device.
                launchedAppID = Self.defaultMediaReceiverAppID
                onNotice?("Eigener Empfänger nicht verfügbar – der Standard-Player von Google wird verwendet.")
                launchReceiverApp()
            } else {
                fail("Cast-App konnte nicht gestartet werden")
            }
        default:
            break
        }
    }

    private func handleMedia(type: String, json: [String: Any]) {
        switch type {
        case "MEDIA_STATUS":
            guard let entries = json["status"] as? [[String: Any]], let entry = entries.first else { return }
            if let id = (entry["mediaSessionId"] as? NSNumber)?.intValue {
                mediaSessionID = id
            }
            let media = entry["media"] as? [String: Any]
            if let duration = (media?["duration"] as? NSNumber)?.doubleValue, duration > 0 {
                lastDuration = duration
            }
            let playerState = entry["playerState"] as? String ?? "IDLE"
            let idleReason = entry["idleReason"] as? String
            if playerState == "IDLE", idleReason != nil {
                // Media session is over; stop polling until the next LOAD.
                mediaSessionID = nil
            }
            onMediaStatus?(MediaStatus(
                playerState: playerState,
                currentTime: (entry["currentTime"] as? NSNumber)?.doubleValue ?? 0,
                duration: lastDuration,
                idleReason: idleReason
            ))
        case "LOAD_FAILED", "INVALID_REQUEST", "INVALID_PLAYER_STATE":
            mediaSessionID = nil
            onMediaStatus?(MediaStatus(
                playerState: "IDLE",
                currentTime: 0,
                duration: lastDuration,
                idleReason: "ERROR"
            ))
        default:
            break
        }
    }

    // MARK: Outgoing messages

    private func sendLoad(_ request: PendingLoad) {
        guard let transportID else {
            pendingLoad = request
            return
        }
        mediaSessionID = nil
        lastDuration = nil

        var metadata: [String: Any] = ["metadataType": 0, "title": request.title]
        if let subtitle = request.subtitle, !subtitle.isEmpty {
            metadata["subtitle"] = subtitle
        }
        if let imageURL = request.imageURL {
            metadata["images"] = [["url": imageURL.absoluteString]]
        }
        let media: [String: Any] = [
            "contentId": request.url.absoluteString,
            "contentType": request.contentType,
            "streamType": "BUFFERED",
            "metadata": metadata
        ]
        send(
            namespace: Self.mediaNS,
            destination: transportID,
            payload: [
                "type": "LOAD",
                "requestId": nextRequestID(),
                "media": media,
                "autoplay": request.autoplay,
                "currentTime": max(0, request.startTime)
            ]
        )
        send(
            namespace: Self.mediaNS,
            destination: transportID,
            payload: ["type": "GET_STATUS", "requestId": nextRequestID()]
        )
    }

    private func sendMediaCommand(_ type: String, extra: [String: Any]) {
        guard state == .connected, let transportID, let mediaSessionID else { return }
        var payload = extra
        payload["type"] = type
        payload["mediaSessionId"] = mediaSessionID
        payload["requestId"] = nextRequestID()
        send(namespace: Self.mediaNS, destination: transportID, payload: payload)
    }

    private func nextRequestID() -> Int {
        requestCounter += 1
        return requestCounter
    }

    private func send(namespace: String, destination: String, payload: [String: Any]) {
        guard let conn = connection else { return }
        let data = frame(namespace, destination, payload)
        conn.send(content: data, completion: .contentProcessed { _ in })
    }

    private func frame(_ namespace: String, _ destination: String, _ payload: [String: Any]) -> Data {
        let json = (try? JSONSerialization.data(withJSONObject: payload)) ?? Data("{}".utf8)
        let message = CastMessage(
            sourceID: Self.senderID,
            destinationID: destination,
            namespace: namespace,
            payload: String(decoding: json, as: UTF8.self)
        )
        return message.framed()
    }

    private func parseJSON(_ text: String) -> [String: Any]? {
        guard let data = text.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) else { return nil }
        return object as? [String: Any]
    }
}
