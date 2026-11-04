import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import AniworldKit

final class ExtractorTests: XCTestCase {
    func testVOEParseEmbedYieldsHLS() throws {
        let url = try XCTUnwrap(VOEExtractor.parseEmbed(try Fixture.text("voe_mirror.html")))
        XCTAssertEqual(url.scheme, "https")
        XCTAssertTrue(url.absoluteString.contains(".m3u8"))
    }

    func testVOEParseEmbedHandlesJunk() {
        XCTAssertNil(VOEExtractor.parseEmbed("<html>no json here</html>"))
        XCTAssertNil(VOEExtractor.parseEmbed(#"<script type="application/json">["not-base64"]</script>"#))
    }

    func testVOEFallsBackToDirectAccessURL() throws {
        // Re-encode {"direct_access_url": ...} with the inverse pipeline.
        let json = #"{"direct_access_url":"https://cdn.example/v.mp4"}"#
        let b1 = Data(json.utf8).base64EncodedString()
        let shifted = String(String.UnicodeScalarView(b1.unicodeScalars.reversed().map { Unicode.Scalar($0.value + 3)! }))
        let outer = VOEExtractor.rot13(Data(shifted.utf8).base64EncodedString())
        let blob = String(decoding: try JSONSerialization.data(withJSONObject: [outer]), as: UTF8.self)
        XCTAssertEqual(VOEExtractor.parseEmbed(#"<script type="application/json">\#(blob)</script>"#)?.absoluteString,
                       "https://cdn.example/v.mp4")
    }

    func testVOEBounceFollowsMirror() async throws {
        let stub = try Fixture.text("voe_embed.html")
        let mirror = try Fixture.text("voe_mirror.html")
        let http = FakeHTTP([
            "https://aniworld.to/redirect/1": FakeHTTP.Canned(status: 200, body: stub,
                                                              finalURL: URL(string: "https://voe.sx/e/yda8qozrvf1c")),
            "https://juliewomanwish.com/e/yda8qozrvf1c": FakeHTTP.ok(mirror),
        ])
        let stream = await VOEExtractor().extract(redirectURL: URL(string: "https://aniworld.to/redirect/1")!, http: http)
        let s = try XCTUnwrap(stream)
        XCTAssertTrue(s.url.absoluteString.contains(".m3u8"))
        XCTAssertEqual(s.headers["Referer"], "https://juliewomanwish.com")
        XCTAssertEqual(s.headers["User-Agent"], AniworldClient.userAgent)
    }

    func testVidmolyParseEmbed() throws {
        let url = try XCTUnwrap(VidmolyExtractor.parseEmbed(try Fixture.text("embed_vidmoly.html")))
        XCTAssertEqual(url.scheme, "https")
        XCTAssertTrue(url.absoluteString.contains(".m3u8"))
        XCTAssertNil(VidmolyExtractor.parseEmbed("<html>nothing</html>"))
    }

    func testRegistryIsCaseInsensitive() {
        XCTAssertNotNil(ExtractorRegistry.default.extractor(for: "VOE"))
        XCTAssertNotNil(ExtractorRegistry.default.extractor(for: "Vidmoly"))
        XCTAssertNil(ExtractorRegistry.default.extractor(for: "Doodstream"))
    }
}

final class OrderingTests: XCTestCase {
    private let prefs = StreamPreferences.default

    func testPrefersLanguageThenHoster() {
        let hosters = [
            hoster("Vidoza", .germanSub), hoster("VOE", .englishSub),
            hoster("Filemoon", .germanDub), hoster("VOE", .germanDub),
        ]
        let ordered = StreamResolver.orderHosters(hosters, language: nil, preferences: prefs)
        XCTAssertEqual(ordered[0].name, "VOE"); XCTAssertEqual(ordered[0].language, .germanDub)
        XCTAssertEqual(ordered[1].name, "Filemoon"); XCTAssertEqual(ordered[1].language, .germanDub)
        XCTAssertEqual(ordered[2].language, .germanSub)
        XCTAssertEqual(ordered[3].language, .englishSub)
    }

    func testDropsUnknownAndUnlistedLanguages() {
        let ordered = StreamResolver.orderHosters([hoster("VOE", nil), hoster("VOE", .germanDub)], language: nil, preferences: prefs)
        XCTAssertEqual(ordered.map(\.language), [.germanDub])
        let only = StreamPreferences(languagePriority: [.englishSub], hosterPriority: ["VOE"])
        let o2 = StreamResolver.orderHosters([hoster("VOE", .germanDub), hoster("VOE", .englishSub)], language: nil, preferences: only)
        XCTAssertEqual(o2.map(\.language), [.englishSub])
    }

    func testRestrictsToChosenLanguage() {
        let hosters = [hoster("VOE", .germanDub), hoster("Vidmoly", .germanSub),
                       hoster("Filemoon", .germanSub), hoster("VOE", .germanSub)]
        let ordered = StreamResolver.orderHosters(hosters, language: .germanSub, preferences: prefs)
        XCTAssertEqual(Set(ordered.map(\.language)), [.germanSub])
        XCTAssertEqual(ordered.map(\.name), ["VOE", "Vidmoly", "Filemoon"])
    }

    func testAvailableLanguagesFollowPriority() {
        let hosters = [hoster("VOE", .englishSub), hoster("Vidmoly", .germanDub), hoster("VOE", .germanSub),
                       hoster("Doodstream", .germanDub), hoster("VOE", nil)]
        XCTAssertEqual(StreamResolver.availableLanguages(hosters, preferences: prefs), [.germanDub, .germanSub, .englishSub])
        let custom = StreamPreferences(languagePriority: [.englishSub], hosterPriority: [])
        XCTAssertEqual(StreamResolver.availableLanguages(hosters, preferences: custom), [.englishSub, .germanDub, .germanSub])  // unlisted keep page order
    }
}

final class LivenessTests: XCTestCase {
    private let master = "https://cdn/x/master.m3u8"
    private let variant = "https://cdn/x/index.m3u8?t=1"
    private let segment = "https://cdn/x/seg0.ts"

    private func hls(segmentStatus: Int) -> FakeHTTP {
        FakeHTTP([
            master: FakeHTTP.ok("#EXTM3U\n#EXT-X-STREAM-INF:BANDWIDTH=1\nindex.m3u8?t=1\n"),
            variant: FakeHTTP.ok("#EXTM3U\n#EXTINF:4,\nseg0.ts\n"),
            segment: FakeHTTP.code(segmentStatus),
        ])
    }

    private func stream(_ url: String) -> ExtractedStream { ExtractedStream(url: URL(string: url)!, headers: ["Referer": "https://r"]) }

    private func resolver(_ http: FakeHTTP, _ registry: ExtractorRegistry = .default) -> StreamResolver {
        StreamResolver(http: http, extractors: registry)
    }

    func testHLSLiveWhenSegmentOK() async {
        let http = hls(segmentStatus: 200)
        let live = await resolver(http).isLive(stream(master))
        XCTAssertTrue(live)
        XCTAssertEqual(http.probed, [segment])
        let partial = await resolver(hls(segmentStatus: 206)).isLive(stream(master))
        XCTAssertTrue(partial)
    }

    func testHLSDeadWhenSegment403() async {
        let live = await resolver(hls(segmentStatus: 403)).isLive(stream(master))
        XCTAssertFalse(live)
    }

    func testDeadWhenPlaylistFails() async {
        let live = await resolver(FakeHTTP([master: FakeHTTP.code(403)])).isLive(stream(master))
        XCTAssertFalse(live)
    }

    func testProgressive() async {
        let url = "https://cdn/video.mp4"
        let ok = await resolver(FakeHTTP([url: FakeHTTP.code(200)])).isLive(stream(url))
        let dead = await resolver(FakeHTTP([url: FakeHTTP.code(403)])).isLive(stream(url))
        XCTAssertTrue(ok)
        XCTAssertFalse(dead)
    }

    func testNetworkErrorIsNotLive() async {
        let http = FakeHTTP(); http.failAll = true
        let live = await resolver(http).isLive(stream(master))
        XCTAssertFalse(live)
    }

    // MARK: Fallback

    private struct StubExtractor: StreamExtractor {
        var result: ExtractedStream?
        func extract(redirectURL: URL, http: HTTPFetching) async -> ExtractedStream? { result }
    }

    private func registry(voe: ExtractedStream?, vidmoly: ExtractedStream?) -> ExtractorRegistry {
        ExtractorRegistry(extractors: ["voe": StubExtractor(result: voe), "vidmoly": StubExtractor(result: vidmoly)])
    }

    func testFallsBackToNextHosterWhenFirstIsDead() async throws {
        let http = FakeHTTP([
            "https://dead/seg.mp4": FakeHTTP.code(403), "https://live/seg.mp4": FakeHTTP.code(200),
        ])
        let reg = registry(voe: stream("https://dead/seg.mp4"), vidmoly: stream("https://live/seg.mp4"))
        let result = try await resolver(http, reg).resolve(
            hosters: [hoster("VOE", .germanDub), hoster("Vidmoly", .germanDub)],
            language: .germanDub, preferences: .default, verify: true, excluding: [])
        XCTAssertEqual(result.hoster, "Vidmoly")
        XCTAssertEqual(result.url.absoluteString, "https://live/seg.mp4")
        XCTAssertEqual(result.language, .germanDub)
    }

    func testVerifyFalseSkipsCheck() async throws {
        let http = FakeHTTP()
        let reg = registry(voe: stream("https://dead/seg.mp4"), vidmoly: nil)
        let result = try await resolver(http, reg).resolve(
            hosters: [hoster("VOE", .germanDub)], language: .germanDub, preferences: .default,
            verify: false, excluding: [])
        XCTAssertEqual(result.hoster, "VOE")
        XCTAssertTrue(http.probed.isEmpty)
    }

    func testExcludingSkipsHosterAndNoneLeftThrows() async throws {
        let reg = registry(voe: stream("https://a/x.mp4"), vidmoly: stream("https://b/x.mp4"))
        let r = resolver(FakeHTTP(), reg)
        let hosters = [hoster("VOE", .germanDub), hoster("Vidmoly", .germanDub)]
        let result = try await r.resolve(hosters: hosters, language: nil, preferences: .default, verify: false, excluding: ["voe"])
        XCTAssertEqual(result.hoster, "Vidmoly")
        do {
            _ = try await r.resolve(hosters: hosters, language: nil, preferences: .default, verify: false,
                                    excluding: ["VOE", "Vidmoly"])
            XCTFail("expected noPlayableStream")
        } catch {
            XCTAssertEqual(error as? AniworldError, .noPlayableStream)
        }
    }

    func testExtractionFailureFallsThrough() async throws {
        let reg = registry(voe: nil, vidmoly: stream("https://b/x.mp4"))
        let result = try await resolver(FakeHTTP(), reg).resolve(
            hosters: [hoster("VOE", .germanDub), hoster("Vidmoly", .germanDub)],
            language: nil, preferences: .default, verify: false, excluding: [])
        XCTAssertEqual(result.hoster, "Vidmoly")
    }
}

final class HTTPClientTests: XCTestCase {
    private actor Counter { var n = 0; func next() -> Int { n += 1; return n } }

    private struct Flaky: HTTPFetching {
        let statuses: [Int]
        let counter = Counter()
        func send(_ request: URLRequest) async throws -> HTTPResponse {
            let i = await counter.next()
            return HTTPResponse(data: Data("ok".utf8), status: statuses[min(i - 1, statuses.count - 1)],
                                url: request.url!, headers: [:])
        }
        func probeStatus(_ request: URLRequest) async throws -> Int { 200 }
    }

    func testRetriesOn5xxThenSucceeds() async throws {
        let client = HTTPClient(transport: Flaky(statuses: [503, 429, 200]), throttle: RequestThrottle(gap: .zero), backoffScale: 0)
        let text = try await client.getText(URL(string: "https://aniworld.to/x")!)
        XCTAssertEqual(text, "ok")
    }

    func testThrowsHTTPErrorForPersistent404() async {
        let client = HTTPClient(transport: Flaky(statuses: [404]), throttle: RequestThrottle(gap: .zero), backoffScale: 0)
        do {
            _ = try await client.getText(URL(string: "https://aniworld.to/x")!)
            XCTFail("expected error")
        } catch {
            XCTAssertEqual(error as? AniworldError, .http(status: 404, url: URL(string: "https://aniworld.to/x")!))
        }
    }

    func testCloudflareDetection() {
        let challenge = HTTPResponse(data: Data("<title>Just a moment...</title>".utf8), status: 403,
                                     url: URL(string: "https://aniworld.to")!, headers: ["server": "cloudflare"])
        XCTAssertTrue(HTTPClient.looksLikeCloudflare(challenge))
        var plain = challenge; plain.headers = [:]
        XCTAssertFalse(HTTPClient.looksLikeCloudflare(plain))
        var ok = challenge; ok.status = 200
        XCTAssertFalse(HTTPClient.looksLikeCloudflare(ok))
    }

    func testCloudflareThrowsTypedError() async {
        struct CF: HTTPFetching {
            func send(_ request: URLRequest) async throws -> HTTPResponse {
                HTTPResponse(data: Data("cf-chl".utf8), status: 503, url: request.url!, headers: ["server": "cloudflare"])
            }
            func probeStatus(_ request: URLRequest) async throws -> Int { 503 }
        }
        let client = HTTPClient(transport: CF(), throttle: RequestThrottle(gap: .zero), backoffScale: 0)
        do {
            _ = try await client.getText(URL(string: "https://aniworld.to")!)
            XCTFail("expected error")
        } catch {
            XCTAssertEqual(error as? AniworldError, .cloudflareChallenge(URL(string: "https://aniworld.to")!))
        }
    }
}
