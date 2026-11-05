import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// A completed HTTP exchange. `url` is the final URL after redirects.
struct HTTPResponse: Sendable {
    var data: Data
    var status: Int
    var url: URL
    /// Header names are lowercased.
    var headers: [String: String]

    var text: String { String(decoding: data, as: UTF8.self) }
}

/// Minimal transport used by the client, extractors and the liveness check.
/// Tests inject fakes.
protocol HTTPFetching: Sendable {
    /// Performs the request and returns the response whatever its status.
    func send(_ request: URLRequest) async throws -> HTTPResponse
    /// Returns the response status without downloading the body.
    func probeStatus(_ request: URLRequest) async throws -> Int
}

extension HTTPFetching {
    /// GET with optional extra headers.
    func get(_ url: URL, headers: [String: String] = [:]) async throws -> HTTPResponse {
        var request = URLRequest(url: url)
        for (key, value) in headers { request.setValue(value, forHTTPHeaderField: key) }
        return try await send(request)
    }
}

/// Spaces out requests per host so we do not hammer the site.
actor RequestThrottle {
    private let gap: Duration
    private var nextSlot: [String: ContinuousClock.Instant] = [:]

    init(gap: Duration = .milliseconds(400)) { self.gap = gap }

    func wait(host: String) async throws {
        let now = ContinuousClock.now
        let slot = max(now, nextSlot[host] ?? now)
        nextSlot[host] = slot + gap
        if slot > now { try await Task.sleep(until: slot, clock: .continuous) }
    }
}

/// Wraps a transport with throttling, retry/backoff for 429/5xx and Cloudflare detection.
final class HTTPClient: HTTPFetching, @unchecked Sendable {
    static let maxRetries = 3
    static let backoffFactor = 0.6

    private let transport: HTTPFetching
    private let throttle: RequestThrottle
    private let backoffScale: Double

    init(transport: HTTPFetching = URLSessionTransport(), throttle: RequestThrottle = RequestThrottle(),
         backoffScale: Double = 1) {
        self.transport = transport
        self.throttle = throttle
        self.backoffScale = backoffScale
    }

    /// Same transport and retry behaviour, but its own throttle (e.g. a shorter gap for paged lists).
    func withThrottle(_ throttle: RequestThrottle) -> HTTPClient {
        HTTPClient(transport: transport, throttle: throttle, backoffScale: backoffScale)
    }

    func send(_ request: URLRequest) async throws -> HTTPResponse {
        var attempt = 0
        while true {
            try await throttle.wait(host: request.url?.host ?? "")
            let response: HTTPResponse
            do {
                response = try await transport.send(request)
            } catch let error as URLError where error.code == .cancelled {
                throw AniworldError.cancelled
            } catch let error as URLError where attempt < Self.maxRetries && Self.isTransient(error) {
                try await backoff(attempt: attempt, retryAfter: nil)
                attempt += 1
                continue
            }
            if Self.looksLikeCloudflare(response) { throw AniworldError.cloudflareChallenge(response.url) }
            if [429, 500, 502, 503, 504].contains(response.status), attempt < Self.maxRetries {
                try await backoff(attempt: attempt, retryAfter: response.headers["retry-after"].flatMap(Double.init))
                attempt += 1
                continue
            }
            return response
        }
    }

    func probeStatus(_ request: URLRequest) async throws -> Int {
        do {
            return try await transport.probeStatus(request)
        } catch let error as URLError where error.code == .cancelled {
            throw AniworldError.cancelled
        }
    }

    /// GET returning the body text; throws `AniworldError.http` for status >= 400.
    func getText(_ url: URL, headers: [String: String] = [:]) async throws -> String {
        let response = try await get(url, headers: headers)
        guard response.status < 400 else { throw AniworldError.http(status: response.status, url: response.url) }
        return response.text
    }

    private func backoff(attempt: Int, retryAfter: Double?) async throws {
        var base = retryAfter ?? Self.backoffFactor * pow(2, Double(attempt))
        if !base.isFinite { base = Self.backoffFactor * pow(2, Double(attempt)) }
        let seconds = max(min(base, 10), 0) * backoffScale
        try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
    }

    private static func isTransient(_ error: URLError) -> Bool {
        [.timedOut, .networkConnectionLost, .cannotConnectToHost, .dnsLookupFailed].contains(error.code)
    }

    static func looksLikeCloudflare(_ response: HTTPResponse) -> Bool {
        guard response.status == 403 || response.status == 503 else { return false }
        guard (response.headers["server"] ?? "").lowercased().contains("cloudflare") else { return false }
        let body = String(response.text.prefix(4000)).lowercased()
        return ["just a moment", "cf-chl", "challenge-platform", "cf-browser-verification"].contains { body.contains($0) }
    }
}

/// URLSession-backed transport (swift-corelibs-foundation as well as Apple platforms).
final class URLSessionTransport: HTTPFetching, @unchecked Sendable {
    static let timeout: TimeInterval = 20

    private let session: URLSession

    init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = Self.timeout
        config.timeoutIntervalForResource = 60
        self.session = URLSession(configuration: config)
    }

    private func prepared(_ request: URLRequest) -> URLRequest {
        var request = request
        if request.value(forHTTPHeaderField: "User-Agent") == nil {
            request.setValue(AniworldClient.userAgent, forHTTPHeaderField: "User-Agent")
        }
        if request.value(forHTTPHeaderField: "Accept-Language") == nil {
            request.setValue("de-DE,de;q=0.9,en;q=0.6", forHTTPHeaderField: "Accept-Language")
        }
        request.timeoutInterval = Self.timeout
        return request
    }

    func send(_ request: URLRequest) async throws -> HTTPResponse {
        let (data, response) = try await load(prepared(request))
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        return HTTPResponse(data: data, status: http.statusCode, url: http.url ?? request.url!,
                            headers: Self.lowercasedHeaders(http))
    }

    func probeStatus(_ request: URLRequest) async throws -> Int {
        var request = prepared(request)
        request.setValue("bytes=0-1", forHTTPHeaderField: "Range")
        let probe = StatusProbe()
        let probeSession = URLSession(configuration: session.configuration, delegate: probe, delegateQueue: nil)
        defer { probeSession.finishTasksAndInvalidate() }
        return try await probe.run(request, in: probeSession)
    }

    private static func lowercasedHeaders(_ response: HTTPURLResponse) -> [String: String] {
        var out: [String: String] = [:]
        for (key, value) in response.allHeaderFields { out["\(key)".lowercased()] = "\(value)" }
        return out
    }

    private func load(_ request: URLRequest) async throws -> (Data, URLResponse) {
        #if canImport(FoundationNetworking)
        // Bridge the callback API: it is the most dependable path on Linux.
        let box = TaskBox()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let task = session.dataTask(with: request) { data, response, error in
                    if let error { continuation.resume(throwing: error) }
                    else if let data, let response { continuation.resume(returning: (data, response)) }
                    else { continuation.resume(throwing: URLError(.badServerResponse)) }
                }
                box.set(task)
                task.resume()
            }
        } onCancel: { box.cancel() }
        #else
        return try await session.data(for: request)
        #endif
    }
}

#if canImport(FoundationNetworking)
private final class TaskBox: @unchecked Sendable {
    private let lock = NSLock()
    private var task: URLSessionTask?
    private var cancelled = false

    func set(_ task: URLSessionTask) {
        lock.lock(); defer { lock.unlock() }
        self.task = task
        if cancelled { task.cancel() }
    }

    func cancel() {
        lock.lock(); defer { lock.unlock() }
        cancelled = true
        task?.cancel()
    }
}
#endif

/// Reads only the status line, then cancels the transfer so segments are not downloaded.
private final class StatusProbe: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Int, Error>?
    private var status: Int?
    private var task: URLSessionTask?

    func run(_ request: URLRequest, in session: URLSession) async throws -> Int {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Int, Error>) in
                lock.lock()
                self.continuation = continuation
                let task = session.dataTask(with: request)
                self.task = task
                lock.unlock()
                task.resume()
            }
        } onCancel: {
            lock.lock(); let task = self.task; lock.unlock()
            task?.cancel()
        }
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
                    completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        if let http = response as? HTTPURLResponse {
            lock.lock(); status = http.statusCode; lock.unlock()
        }
        completionHandler(.cancel)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        lock.lock()
        let continuation = self.continuation
        self.continuation = nil
        let status = self.status
        lock.unlock()
        if let status { continuation?.resume(returning: status) }
        else { continuation?.resume(throwing: error ?? URLError(.badServerResponse)) }
    }
}
