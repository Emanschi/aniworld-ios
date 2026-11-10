import Foundation
import Network
#if canImport(Darwin)
import Darwin
#endif

/// Small HTTP/1.1 server on the phone's Wi-Fi address that relays a stream to cast receivers.
///
/// A Chromecast cannot send custom HTTP headers (Referer / User-Agent required by the VOE and
/// Vidmoly CDNs) and cannot read files from the phone, so the phone serves the stream itself:
///
/// - Remote source: `http://<ip>:<port>/<token>/r/<percent-encoded absolute upstream URL>`
///   The request is forwarded with the headers registered for `<token>`. HLS playlists are
///   rewritten so that every referenced playlist, segment and key is fetched through the proxy too.
/// - Local file: `http://<ip>:<port>/<token>/f/<path relative to the registered directory>`
///   The file is served from disk with Range support. The directory structure is preserved, so
///   relative paths inside local playlists keep working.
final class CastStreamProxy: @unchecked Sendable {
    static let shared = CastStreamProxy()

    enum ProxyError: Error {
        case listenerFailed
        case notReady
    }

    fileprivate enum Entry {
        case remote(headers: [String: String])
        case local(root: URL)
    }

    /// Maximum size of a playlist body that is buffered for rewriting.
    fileprivate static let maxBufferedBody = 2 * 1024 * 1024
    /// Read size for local files.
    fileprivate static let fileChunk = 512 * 1024
    private static let maxTokens = 64

    fileprivate let queue = DispatchQueue(label: "de.aniworld.cast-proxy")
    private let startLock = NSLock()
    private let lock = NSLock()

    // Guarded by `lock`.
    private var listener: NWListener?
    private var port: UInt16?
    private var entries: [String: Entry] = [:]
    private var tokenOrder: [String] = []
    private var connections: [ObjectIdentifier: ProxyConnection] = [:]

    fileprivate let router = UpstreamRouter()
    fileprivate let session: URLSession

    private init() {
        let config = URLSessionConfiguration.ephemeral
        config.urlCache = nil
        config.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        config.httpCookieStorage = nil
        config.httpShouldSetCookies = false
        config.timeoutIntervalForRequest = 30
        let delegateQueue = OperationQueue()
        delegateQueue.maxConcurrentOperationCount = 1
        delegateQueue.name = "de.aniworld.cast-proxy.upstream"
        session = URLSession(configuration: config, delegate: router, delegateQueue: delegateQueue)
    }

    // MARK: Lifecycle

    /// Starts the listener (random free port) if needed. Safe to call repeatedly.
    func start() throws {
        startLock.lock()
        defer { startLock.unlock() }

        lock.lock()
        let alreadyRunning = listener != nil && port != nil
        lock.unlock()
        if alreadyRunning { return }

        // Drop a half-started listener from an earlier attempt.
        stopListenerLocked()

        let newListener: NWListener
        do {
            newListener = try NWListener(using: .tcp)
        } catch {
            throw ProxyError.listenerFailed
        }

        let semaphore = DispatchSemaphore(value: 0)
        newListener.stateUpdateHandler = { [weak self, weak newListener] state in
            guard let self, let newListener else { return }
            switch state {
            case .ready:
                self.lock.lock()
                self.port = newListener.port?.rawValue
                self.lock.unlock()
                semaphore.signal()
            case .failed, .cancelled:
                self.lock.lock()
                if self.listener === newListener {
                    self.listener = nil
                    self.port = nil
                }
                self.lock.unlock()
                semaphore.signal()
            default:
                break
            }
        }
        newListener.newConnectionHandler = { [weak self] connection in
            self?.accept(connection)
        }

        lock.lock()
        listener = newListener
        lock.unlock()
        newListener.start(queue: queue)

        _ = semaphore.wait(timeout: .now() + 2)

        lock.lock()
        let ready = port != nil
        lock.unlock()
        if !ready {
            stopListenerLocked()
            throw ProxyError.notReady
        }
    }

    func stop() {
        startLock.lock()
        defer { startLock.unlock() }
        stopListenerLocked()
        lock.lock()
        entries.removeAll()
        tokenOrder.removeAll()
        lock.unlock()
    }

    /// Cancels the listener and all open connections. Caller holds `startLock`.
    private func stopListenerLocked() {
        lock.lock()
        let oldListener = listener
        let open = Array(connections.values)
        listener = nil
        port = nil
        lock.unlock()
        oldListener?.cancel()
        for connection in open {
            connection.finish()
        }
    }

    // MARK: Public URLs

    /// LAN URL the receiver can fetch for `source` (remote http(s) URL with headers, or a local file URL).
    /// Returns nil if there is no Wi-Fi IPv4 address or the listener is not ready.
    func publicURL(for source: URL, headers: [String: String]) -> URL? {
        lock.lock()
        let currentPort = port
        lock.unlock()
        guard let currentPort, let ip = Self.wifiIPv4Address() else { return nil }
        let origin = "http://\(ip):\(currentPort)"

        if source.isFileURL {
            guard let local = Self.localRootAndRelativePath(for: source) else { return nil }
            let token = register(.local(root: local.root))
            let path = local.relative
                .split(separator: "/")
                .map { Self.encodeComponent(String($0)) }
                .joined(separator: "/")
            return URL(string: "\(origin)/\(token)/f/\(path)")
        }

        guard let scheme = source.scheme?.lowercased(), scheme == "http" || scheme == "https" else { return nil }
        let token = register(.remote(headers: headers))
        return URL(string: "\(origin)/\(token)/r/\(Self.encodeComponent(source.absoluteString))")
    }

    /// "application/x-mpegURL" for HLS (.m3u8, or a local .movpkg/HLS folder if applicable), otherwise "video/mp4".
    static func contentType(for url: URL) -> String {
        let ext = url.pathExtension.lowercased()
        if ext == "m3u8" || ext == "movpkg" || url.path.lowercased().contains(".m3u8") {
            return "application/x-mpegURL"
        }
        return "video/mp4"
    }

    private func register(_ entry: Entry) -> String {
        let token = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
        lock.lock()
        entries[token] = entry
        tokenOrder.append(token)
        while tokenOrder.count > Self.maxTokens {
            let oldest = tokenOrder.removeFirst()
            entries.removeValue(forKey: oldest)
        }
        lock.unlock()
        return token
    }

    fileprivate func entry(for token: String) -> Entry? {
        lock.lock()
        defer { lock.unlock() }
        return entries[token]
    }

    // MARK: Connections

    private func accept(_ nwConnection: NWConnection) {
        let connection = ProxyConnection(connection: nwConnection, proxy: self)
        lock.lock()
        connections[ObjectIdentifier(connection)] = connection
        lock.unlock()
        connection.start()
    }

    fileprivate func release(_ connection: ProxyConnection) {
        lock.lock()
        connections.removeValue(forKey: ObjectIdentifier(connection))
        lock.unlock()
    }

    // MARK: Helpers

    /// Percent-encodes everything except unreserved characters (so "/" and ":" are encoded too).
    fileprivate static func encodeComponent(_ value: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }

    /// Directory that is exposed for a local source plus the file path relative to it.
    /// For a directory (HLS package) the shortest `.m3u8` inside is used as the entry point.
    private static func localRootAndRelativePath(for source: URL) -> (root: URL, relative: String)? {
        let resolved = source.standardizedFileURL.resolvingSymlinksInPath()
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: resolved.path, isDirectory: &isDirectory) else { return nil }

        if !isDirectory.boolValue {
            return (resolved.deletingLastPathComponent(), resolved.lastPathComponent)
        }

        guard let enumerator = FileManager.default.enumerator(at: resolved, includingPropertiesForKeys: nil) else {
            return nil
        }
        var best: URL?
        for case let item as URL in enumerator where item.pathExtension.lowercased() == "m3u8" {
            if let current = best {
                if item.path.count < current.path.count { best = item }
            } else {
                best = item
            }
        }
        guard let playlist = best?.resolvingSymlinksInPath() else { return nil }
        let prefix = resolved.path.hasSuffix("/") ? resolved.path : resolved.path + "/"
        guard playlist.path.hasPrefix(prefix) else { return nil }
        return (resolved, String(playlist.path.dropFirst(prefix.count)))
    }

    /// Wi-Fi IPv4 address: prefers "en0", falls back to any other private IPv4 (e.g. bridge100 hotspot).
    private static func wifiIPv4Address() -> String? {
        var head: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&head) == 0, let first = head else { return nil }
        defer { freeifaddrs(head) }

        var preferred: String?
        var fallback: String?
        var cursor: UnsafeMutablePointer<ifaddrs>? = first
        while let current = cursor {
            cursor = current.pointee.ifa_next

            let flags = Int32(current.pointee.ifa_flags)
            guard (flags & IFF_UP) != 0, (flags & IFF_LOOPBACK) == 0,
                  let addr = current.pointee.ifa_addr,
                  addr.pointee.sa_family == sa_family_t(AF_INET) else { continue }

            var hostBuffer = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            let result = getnameinfo(addr, socklen_t(addr.pointee.sa_len),
                                     &hostBuffer, socklen_t(hostBuffer.count),
                                     nil, 0, NI_NUMERICHOST)
            guard result == 0 else { continue }
            let address = String(cString: hostBuffer)
            let name = String(cString: current.pointee.ifa_name)

            if name == "en0" {
                preferred = address
            } else if fallback == nil, isPrivateIPv4(address) {
                fallback = address
            }
        }
        return preferred ?? fallback
    }

    private static func isPrivateIPv4(_ address: String) -> Bool {
        let parts = address.split(separator: ".").compactMap { Int($0) }
        guard parts.count == 4 else { return false }
        if parts[0] == 10 { return true }
        if parts[0] == 172, (16...31).contains(parts[1]) { return true }
        if parts[0] == 192, parts[1] == 168 { return true }
        return false
    }

    // MARK: Playlist rewriting

    /// Rewrites all URIs of an HLS playlist so they point back through the proxy.
    fileprivate static func rewritePlaylist(_ text: String, base: URL, origin: String, token: String) -> String {
        func proxied(_ reference: String) -> String {
            let trimmed = reference.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty,
                  let absolute = URL(string: trimmed, relativeTo: base)?.absoluteURL,
                  let scheme = absolute.scheme?.lowercased(),
                  scheme == "http" || scheme == "https" else { return reference }
            return "\(origin)/\(token)/r/\(encodeComponent(absolute.absoluteString))"
        }

        let attribute = try? NSRegularExpression(pattern: "URI=\"([^\"]*)\"", options: [])

        var output: [String] = []
        for rawLine in text.components(separatedBy: "\n") {
            let line = rawLine.trimmingCharacters(in: CharacterSet(charactersIn: "\r"))
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty {
                output.append(line)
            } else if trimmed.hasPrefix("#") {
                guard let attribute else {
                    output.append(line)
                    continue
                }
                let nsLine = line as NSString
                var result = line
                let matches = attribute.matches(in: line, options: [], range: NSRange(location: 0, length: nsLine.length))
                // Replace back to front so earlier ranges stay valid.
                for match in matches.reversed() where match.numberOfRanges >= 2 {
                    let uri = nsLine.substring(with: match.range(at: 1))
                    let replacement = "URI=\"\(proxied(uri))\""
                    result = (result as NSString).replacingCharacters(in: match.range, with: replacement)
                }
                output.append(result)
            } else {
                output.append(proxied(trimmed))
            }
        }
        return output.joined(separator: "\n")
    }

    fileprivate static func localMimeType(for url: URL) -> String {
        switch url.pathExtension.lowercased() {
        case "mp4", "m4v", "m4s", "fmp4", "cmfv", "cmfa", "m4a": return "video/mp4"
        case "ts": return "video/mp2t"
        case "m3u8": return "application/vnd.apple.mpegurl"
        case "aac": return "audio/aac"
        case "vtt": return "text/vtt"
        default: return "application/octet-stream" // includes "key"
        }
    }
}

// MARK: - Upstream delegate routing

/// Routes the callbacks of the shared upstream URLSession to the connection that owns the task.
private final class UpstreamRouter: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private var handlers: [Int: ProxyConnection] = [:]

    func register(_ task: URLSessionTask, handler: ProxyConnection) {
        lock.lock()
        handlers[task.taskIdentifier] = handler
        lock.unlock()
    }

    private func handler(for task: URLSessionTask) -> ProxyConnection? {
        lock.lock()
        defer { lock.unlock() }
        return handlers[task.taskIdentifier]
    }

    private func remove(_ task: URLSessionTask) {
        lock.lock()
        handlers.removeValue(forKey: task.taskIdentifier)
        lock.unlock()
    }

    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        guard let owner = handler(for: task) else {
            completionHandler(request)
            return
        }
        completionHandler(owner.requestForRedirect(request))
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask,
                    didReceive response: URLResponse,
                    completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        completionHandler(.allow)
        handler(for: dataTask)?.upstreamDidReceive(response)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        handler(for: dataTask)?.upstreamDidReceive(data)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        let owner = handler(for: task)
        remove(task)
        owner?.upstreamDidComplete(error)
    }
}

// MARK: - One client connection

/// Handles exactly one request on one accepted connection (`Connection: close`).
/// All mutable state is confined to `proxy.queue`.
private final class ProxyConnection: @unchecked Sendable {
    private enum UpstreamMode {
        case stream
        case buffer
    }

    private enum RangeResult {
        case full
        case partial(UInt64, UInt64)
        case unsatisfiable
    }

    private let connection: NWConnection
    private let proxy: CastStreamProxy
    private var queue: DispatchQueue { proxy.queue }

    private var requestBuffer = Data()
    private var finished = false
    /// Set once the final response bytes were handed to the connection.
    private var closing = false

    // Request context
    private var token = ""
    private var origin = ""
    private var isHead = false
    private var upstreamHeaders: [String: String] = [:]
    private var rangeHeader: String?

    // Upstream state
    private var task: URLSessionDataTask?
    private var mode: UpstreamMode = .stream
    private var upstreamResponse: HTTPURLResponse?
    private var headSent = false
    private var bodyBuffer = Data()
    private var pendingBytes = 0
    private var suspended = false

    private static let reasons: [Int: String] = [
        200: "OK", 204: "No Content", 206: "Partial Content", 301: "Moved Permanently",
        302: "Found", 304: "Not Modified", 400: "Bad Request", 403: "Forbidden",
        404: "Not Found", 405: "Method Not Allowed", 416: "Range Not Satisfiable",
        500: "Internal Server Error", 502: "Bad Gateway"
    ]

    init(connection: NWConnection, proxy: CastStreamProxy) {
        self.connection = connection
        self.proxy = proxy
    }

    func start() {
        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .failed, .cancelled:
                self?.finish()
            default:
                break
            }
        }
        connection.start(queue: queue)
        receiveRequest()
    }

    /// Tears everything down. Safe to call from any thread and more than once.
    func finish() {
        queue.async { [self] in
            guard !finished else { return }
            finished = true
            task?.cancel()
            task = nil
            connection.stateUpdateHandler = nil
            connection.cancel()
            proxy.release(self)
        }
    }

    // MARK: Request parsing

    private func receiveRequest() {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 16 * 1024) { [self] data, _, isComplete, error in
            if finished { return }
            if let data { requestBuffer.append(data) }
            if let end = requestBuffer.range(of: Data("\r\n\r\n".utf8)) {
                let head = String(decoding: requestBuffer[..<end.lowerBound], as: UTF8.self)
                handleRequest(head)
                return
            }
            if error != nil || isComplete || requestBuffer.count > 64 * 1024 {
                finish()
                return
            }
            receiveRequest()
        }
    }

    private func handleRequest(_ head: String) {
        let lines = head.components(separatedBy: "\r\n")
        let parts = (lines.first ?? "").split(separator: " ")
        guard parts.count >= 2 else {
            sendSimple(status: 400, text: "Bad Request")
            return
        }
        let method = parts[0].uppercased()
        var target = String(parts[1])

        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let name = line[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
            let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            headers[name] = value
        }

        if method == "OPTIONS" {
            // CORS preflight from the receiver web page.
            sendSimple(status: 204, text: "", extra: [
                ("Access-Control-Allow-Methods", "GET, HEAD, OPTIONS"),
                ("Access-Control-Allow-Headers", "Range, Content-Type"),
                ("Access-Control-Max-Age", "86400")
            ])
            return
        }
        guard method == "GET" || method == "HEAD" else {
            sendSimple(status: 405, text: "Method Not Allowed", extra: [("Allow", "GET, HEAD, OPTIONS")])
            return
        }
        isHead = method == "HEAD"
        rangeHeader = headers["range"]
        origin = "http://" + (headers["host"] ?? "localhost")

        if let query = target.firstIndex(of: "?") { target = String(target[..<query]) }
        guard target.hasPrefix("/") else {
            sendSimple(status: 400, text: "Bad Request")
            return
        }
        let segments = target.dropFirst().split(separator: "/", maxSplits: 2, omittingEmptySubsequences: false)
        guard segments.count == 3 else {
            sendSimple(status: 404, text: "Not Found")
            return
        }
        token = String(segments[0])
        let kind = String(segments[1])
        let rest = String(segments[2])

        guard let entry = proxy.entry(for: token) else {
            sendSimple(status: 404, text: "Not Found")
            return
        }
        switch entry {
        case .remote(let storedHeaders):
            guard kind == "r", let decoded = rest.removingPercentEncoding,
                  let url = URL(string: decoded),
                  let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else {
                sendSimple(status: 404, text: "Not Found")
                return
            }
            upstreamHeaders = storedHeaders
            startUpstream(url: url)
        case .local(let root):
            guard kind == "f", let decoded = rest.removingPercentEncoding else {
                sendSimple(status: 404, text: "Not Found")
                return
            }
            serveLocal(root: root, relativePath: decoded)
        }
    }

    // MARK: Sending

    private func headData(status: Int, headers: [(String, String)]) -> Data {
        var text = "HTTP/1.1 \(status) \(Self.reasons[status] ?? "Status")\r\n"
        for (name, value) in headers {
            text += "\(name): \(value)\r\n"
        }
        text += "Access-Control-Allow-Origin: *\r\n"
        text += "Access-Control-Expose-Headers: Content-Length, Content-Range, Accept-Ranges\r\n"
        text += "Connection: close\r\n\r\n"
        return Data(text.utf8)
    }

    private func sendSimple(status: Int, text: String, extra: [(String, String)] = []) {
        let body = Data(text.utf8)
        var headers: [(String, String)] = [
            ("Content-Type", "text/plain; charset=utf-8"),
            ("Content-Length", String(body.count))
        ]
        headers.append(contentsOf: extra)
        var payload = headData(status: status, headers: headers)
        if !isHead { payload.append(body) }
        headSent = true
        sendFinal(payload)
    }

    /// Sends `data` (may be nil) and closes the connection once it is written.
    private func sendFinal(_ data: Data?) {
        guard !finished, !closing else { return }
        closing = true
        connection.send(content: data, contentContext: .finalMessage, isComplete: true,
                        completion: .contentProcessed { [self] _ in
            finish()
        })
    }

    // MARK: Local files

    private func serveLocal(root: URL, relativePath: String) {
        let rootResolved = root.standardizedFileURL.resolvingSymlinksInPath()
        let fileURL = rootResolved.appendingPathComponent(relativePath).standardizedFileURL.resolvingSymlinksInPath()
        let prefix = rootResolved.path.hasSuffix("/") ? rootResolved.path : rootResolved.path + "/"

        // Only files below the registered directory may be served (no path traversal).
        var isDirectory: ObjCBool = false
        guard fileURL.path.hasPrefix(prefix),
              FileManager.default.fileExists(atPath: fileURL.path, isDirectory: &isDirectory),
              !isDirectory.boolValue else {
            sendSimple(status: 404, text: "Not Found")
            return
        }

        let size: UInt64
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)
            size = (attributes[.size] as? NSNumber)?.uint64Value ?? 0
        } catch {
            sendSimple(status: 404, text: "Not Found")
            return
        }

        var status = 200
        var start: UInt64 = 0
        var length = size
        var headers: [(String, String)] = [
            ("Content-Type", CastStreamProxy.localMimeType(for: fileURL)),
            ("Accept-Ranges", "bytes")
        ]

        switch Self.parseRange(rangeHeader, size: size) {
        case .full:
            break
        case .partial(let first, let last):
            status = 206
            start = first
            length = last - first + 1
            headers.append(("Content-Range", "bytes \(first)-\(last)/\(size)"))
        case .unsatisfiable:
            sendSimple(status: 416, text: "Range Not Satisfiable", extra: [("Content-Range", "bytes */\(size)")])
            return
        }
        headers.append(("Content-Length", String(length)))
        let head = headData(status: status, headers: headers)

        if isHead || length == 0 {
            headSent = true
            sendFinal(head)
            return
        }

        let handle: FileHandle
        do {
            handle = try FileHandle(forReadingFrom: fileURL)
            if start > 0 { try handle.seek(toOffset: start) }
        } catch {
            sendSimple(status: 404, text: "Not Found")
            return
        }
        headSent = true
        let bodyLength = length
        connection.send(content: head, completion: .contentProcessed { [self] error in
            if error != nil {
                try? handle.close()
                finish()
                return
            }
            pumpFile(handle, remaining: bodyLength)
        })
    }

    /// Reads and sends the file chunk by chunk; the next chunk is read once the previous one was written.
    private func pumpFile(_ handle: FileHandle, remaining: UInt64) {
        if finished {
            try? handle.close()
            return
        }
        if remaining == 0 {
            try? handle.close()
            sendFinal(nil)
            return
        }
        let count = Int(min(remaining, UInt64(CastStreamProxy.fileChunk)))
        var chunk: Data?
        do {
            chunk = try handle.read(upToCount: count)
        } catch {
            chunk = nil
        }
        guard let data = chunk, !data.isEmpty else {
            // File shorter than announced: abort so the receiver notices.
            try? handle.close()
            finish()
            return
        }
        connection.send(content: data, completion: .contentProcessed { [self] error in
            if error != nil {
                try? handle.close()
                finish()
                return
            }
            pumpFile(handle, remaining: remaining - UInt64(data.count))
        })
    }

    private static func parseRange(_ header: String?, size: UInt64) -> RangeResult {
        guard let header, header.lowercased().hasPrefix("bytes=") else { return .full }
        let spec = String(header.dropFirst("bytes=".count))
        let firstSpec = spec.split(separator: ",").first.map(String.init) ?? ""
        let parts = firstSpec.split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
        guard parts.count == 2 else { return .full }
        guard size > 0 else { return .unsatisfiable }

        if parts[0].isEmpty {
            guard let suffix = UInt64(parts[1]), suffix > 0 else { return .unsatisfiable }
            let first = size > suffix ? size - suffix : 0
            return .partial(first, size - 1)
        }
        guard let first = UInt64(parts[0]), first < size else { return .unsatisfiable }
        var last = size - 1
        if !parts[1].isEmpty {
            guard let requested = UInt64(parts[1]), requested >= first else { return .unsatisfiable }
            last = min(requested, size - 1)
        }
        return .partial(first, last)
    }

    // MARK: Upstream (remote)

    private func buildRequest(url: URL) -> URLRequest {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalAndRemoteCacheData, timeoutInterval: 30)
        request.httpMethod = isHead ? "HEAD" : "GET"
        for (name, value) in upstreamHeaders {
            request.setValue(value, forHTTPHeaderField: name)
        }
        if let rangeHeader {
            request.setValue(rangeHeader, forHTTPHeaderField: "Range")
        }
        // Avoid transparent decompression so Content-Length stays truthful.
        request.setValue("identity", forHTTPHeaderField: "Accept-Encoding")
        return request
    }

    private func startUpstream(url: URL) {
        let dataTask = proxy.session.dataTask(with: buildRequest(url: url))
        task = dataTask
        proxy.router.register(dataTask, handler: self)
        dataTask.resume()
    }

    /// Called on the URLSession delegate queue: re-applies the stored headers on redirects.
    /// Only reads values that are not mutated after `startUpstream`.
    func requestForRedirect(_ redirect: URLRequest) -> URLRequest {
        guard let url = redirect.url else { return redirect }
        return buildRequest(url: url)
    }

    func upstreamDidReceive(_ response: URLResponse) {
        queue.async { [self] in
            guard !finished, !closing, let http = response as? HTTPURLResponse else { return }
            upstreamResponse = http
            mode = Self.mode(for: http, isHead: isHead)
            if mode == .stream {
                sendUpstreamHead(http, playlist: Self.isDeclaredPlaylist(http))
            }
        }
    }

    func upstreamDidReceive(_ data: Data) {
        queue.async { [self] in
            guard !finished, !closing else { return }
            switch mode {
            case .buffer:
                bodyBuffer.append(data)
                if bodyBuffer.count > 8 * CastStreamProxy.maxBufferedBody {
                    // Far larger than any playlist: give up instead of holding unbounded data.
                    task?.cancel()
                    sendSimple(status: 502, text: "Bad Gateway")
                }
            case .stream:
                guard headSent else { return }
                let size = data.count
                pendingBytes += size
                connection.send(content: data, completion: .contentProcessed { [self] error in
                    pendingBytes -= size
                    if error != nil {
                        finish()
                        return
                    }
                    if suspended && pendingBytes < 1024 * 1024 {
                        suspended = false
                        task?.resume()
                    }
                })
                // Backpressure: pause the download while the receiver reads slower than upstream delivers.
                if !suspended && pendingBytes > 4 * 1024 * 1024 {
                    suspended = true
                    task?.suspend()
                }
            }
        }
    }

    func upstreamDidComplete(_ error: Error?) {
        queue.async { [self] in
            guard !finished, !closing else { return }
            if error != nil {
                if headSent {
                    finish()
                } else {
                    sendSimple(status: 502, text: "Bad Gateway")
                }
                return
            }
            guard let http = upstreamResponse else {
                sendSimple(status: 502, text: "Bad Gateway")
                return
            }
            switch mode {
            case .stream:
                sendFinal(nil)
            case .buffer:
                finishBufferedResponse(http)
            }
        }
    }

    private func finishBufferedResponse(_ http: HTTPURLResponse) {
        let text = String(data: bodyBuffer, encoding: .utf8) ?? String(data: bodyBuffer, encoding: .isoLatin1)
        if http.statusCode == 200, let text,
           text.trimmingCharacters(in: CharacterSet(charactersIn: "\u{FEFF} \t\r\n")).hasPrefix("#EXTM3U") {
            let base = http.url ?? URL(string: "http://localhost/")!
            let rewritten = CastStreamProxy.rewritePlaylist(text, base: base, origin: origin, token: token)
            let body = Data(rewritten.utf8)
            var payload = headData(status: 200, headers: [
                ("Content-Type", "application/vnd.apple.mpegurl"),
                ("Content-Length", String(body.count)),
                ("Cache-Control", "no-store")
            ])
            payload.append(body)
            headSent = true
            sendFinal(payload)
            return
        }

        // Not a playlist: pass the buffered body through unchanged.
        var payload = headData(status: http.statusCode,
                               headers: Self.passthroughHeaders(http, contentLength: bodyBuffer.count))
        payload.append(bodyBuffer)
        headSent = true
        sendFinal(payload)
    }

    private func sendUpstreamHead(_ http: HTTPURLResponse, playlist: Bool) {
        // A rewritten playlist has a different length than upstream, so HEAD answers omit it.
        let length = (playlist && isHead) ? nil : Self.headerContentLength(http)
        var headers = Self.passthroughHeaders(http, contentLength: length)
        if playlist {
            headers = headers.filter { $0.0 != "Content-Type" }
            headers.append(("Content-Type", "application/vnd.apple.mpegurl"))
        }
        headSent = true
        connection.send(content: headData(status: http.statusCode, headers: headers),
                        completion: .contentProcessed { [self] error in
            if error != nil { finish() }
        })
    }

    // MARK: Upstream response helpers

    private static func isDeclaredPlaylist(_ http: HTTPURLResponse) -> Bool {
        let mime = (http.mimeType ?? "").lowercased()
        let ext = http.url?.pathExtension.lowercased() ?? ""
        return mime.contains("mpegurl") || ext == "m3u8"
    }

    private static func headerContentLength(_ http: HTTPURLResponse) -> Int? {
        guard let value = http.value(forHTTPHeaderField: "Content-Length"), let length = Int(value) else { return nil }
        return length
    }

    private static func mode(for http: HTTPURLResponse, isHead: Bool) -> UpstreamMode {
        guard !isHead, (200..<300).contains(http.statusCode) else { return .stream }
        if isDeclaredPlaylist(http) { return .buffer }
        // Playlists are sometimes served as text/plain or octet-stream: sniff small bodies.
        let mime = (http.mimeType ?? "").lowercased()
        let sniffable = mime.isEmpty || mime.hasPrefix("text/") || mime == "application/octet-stream"
        if sniffable, let length = headerContentLength(http), length <= CastStreamProxy.maxBufferedBody {
            return .buffer
        }
        return .stream
    }

    private static func passthroughHeaders(_ http: HTTPURLResponse, contentLength: Int?) -> [(String, String)] {
        var headers: [(String, String)] = []
        let type = http.value(forHTTPHeaderField: "Content-Type")
            ?? http.url.map { CastStreamProxy.localMimeType(for: $0) }
            ?? "application/octet-stream"
        headers.append(("Content-Type", type))
        if let contentLength { headers.append(("Content-Length", String(contentLength))) }
        if let range = http.value(forHTTPHeaderField: "Content-Range") { headers.append(("Content-Range", range)) }
        if let accept = http.value(forHTTPHeaderField: "Accept-Ranges") { headers.append(("Accept-Ranges", accept)) }
        return headers
    }
}
