import XCTest
@testable import AniworldKit

final class GenrePagingTests: XCTestCase {
    private func page(_ slugs: [String], last: Int) -> String {
        let items = slugs.map {
            "<div class=\"seriesListContainer\"><a href=\"/anime/stream/\($0)\"><h3>\($0.uppercased())</h3></a></div>"
        }.joined()
        return "<html><body>\(items)<a href=\"/genre/test/2\">2</a><a href=\"/genre/test/\(last)\">Ende</a></body></html>"
    }

    private final class Collected: @unchecked Sendable {
        private let lock = NSLock()
        private var counts: [Int] = []
        func add(_ n: Int) { lock.lock(); counts.append(n); lock.unlock() }
        var all: [Int] { lock.lock(); defer { lock.unlock() }; return counts }
    }

    private func makeClient(_ http: FakeHTTP, cache: URL?) -> AniworldClient {
        AniworldClient(baseURL: AniworldClient.defaultBaseURL,
                       http: HTTPClient(transport: http, throttle: RequestThrottle(gap: .zero), backoffScale: 0),
                       extractors: .default, skipTransport: FakeHTTP(), genreCacheDirectory: cache)
    }

    func testPagesMergeInOrderWithProgressAndDiskCache() async throws {
        let base = "https://aniworld.to/genre/test"
        let http = FakeHTTP([
            base: FakeHTTP.ok(page(["a", "b"], last: 3)),
            base + "/2": FakeHTTP.ok(page(["c", "a"], last: 3)),
            base + "/3": FakeHTTP.ok(page(["d"], last: 3)),
        ])
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("genre-test-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }

        let progress = Collected()
        let client = makeClient(http, cache: dir)
        let list = try await client.series(inGenre: "Test", progress: { progress.add($0.count) })
        XCTAssertEqual(list.map(\.slug), ["a", "b", "c", "d"])
        XCTAssertEqual(progress.all.first, 2, "first page is reported right away")
        XCTAssertEqual(progress.all.last, 4)
        XCTAssertEqual(progress.all, progress.all.sorted(), "the list only grows")

        // A new client (app restart) reads the disk cache without touching the network.
        let offline = FakeHTTP()
        offline.failAll = true
        let cached = try await makeClient(offline, cache: dir).series(inGenre: "test")
        XCTAssertEqual(cached.map(\.slug), ["a", "b", "c", "d"])
        XCTAssertTrue(offline.requested.isEmpty)
    }

    func testMergeDedupesAcrossPages() {
        let s = { (slug: String) in SeriesSummary(slug: slug, title: slug, url: URL(string: "https://x/\(slug)")!) }
        let merged = AniworldClient.merge([2: [s("b"), s("a")], 1: [s("a")], 3: [s("c")]])
        XCTAssertEqual(merged.map(\.slug), ["a", "b", "c"])
    }
}
