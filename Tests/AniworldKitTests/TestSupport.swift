import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import AniworldKit

enum Fixture {
    static func data(_ name: String) throws -> Data {
        let url = Bundle.module.resourceURL!.appendingPathComponent("Fixtures/\(name)")
        return try Data(contentsOf: url)
    }

    static func text(_ name: String) throws -> String { String(decoding: try data(name), as: UTF8.self) }
}

/// Canned transport: exact URL -> response (404 when unknown); records requests.
final class FakeHTTP: HTTPFetching, @unchecked Sendable {
    struct Canned { var status: Int; var body: String; var finalURL: URL? }

    private let lock = NSLock()
    private var routes: [String: Canned]
    private(set) var requested: [String] = []
    private(set) var probed: [String] = []
    var failAll = false

    init(_ routes: [String: Canned] = [:]) { self.routes = routes }

    static func ok(_ body: String = "") -> Canned { Canned(status: 200, body: body, finalURL: nil) }
    static func code(_ code: Int) -> Canned { Canned(status: code, body: "", finalURL: nil) }

    private func record(_ url: String, probe: Bool) {
        lock.lock(); defer { lock.unlock() }
        if probe { probed.append(url) } else { requested.append(url) }
    }

    func send(_ request: URLRequest) async throws -> HTTPResponse {
        if failAll { throw URLError(.notConnectedToInternet) }
        let url = request.url!
        record(url.absoluteString, probe: false)
        let canned = routes[url.absoluteString] ?? FakeHTTP.code(404)
        return HTTPResponse(data: Data(canned.body.utf8), status: canned.status,
                            url: canned.finalURL ?? url, headers: [:])
    }

    func probeStatus(_ request: URLRequest) async throws -> Int {
        if failAll { throw URLError(.notConnectedToInternet) }
        let url = request.url!.absoluteString
        record(url, probe: true)
        return (routes[url] ?? FakeHTTP.code(404)).status
    }
}

func hoster(_ name: String, _ language: StreamLanguage?, id: String = "") -> HosterLink {
    HosterLink(name: name, language: language, languageKey: 0,
               redirectURL: URL(string: "https://aniworld.to/redirect/\(name)-\(language?.rawValue ?? "none")\(id)")!)
}
