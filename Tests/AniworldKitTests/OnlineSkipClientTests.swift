import XCTest
@testable import AniworldKit

final class OnlineSkipClientTests: XCTestCase {
    private let aniList = "https://graphql.anilist.co"
    private func aniSkip(_ mal: Int, _ ep: Int) -> String {
        "https://api.aniskip.com/v2/skip-times/\(mal)/\(ep)?types=op&types=ed&types=mixed-op&types=mixed-ed&types=recap&episodeLength=0"
    }

    private let skipJSON = """
    {"found":true,"results":[
      {"interval":{"startTime":1300.5,"endTime":1390.5},"skipType":"ed","skipId":"b","episodeLength":1420.1},
      {"interval":{"startTime":60.0,"endTime":150.0},"skipType":"op","skipId":"a","episodeLength":1420.1},
      {"interval":{"startTime":10.0,"endTime":5.0},"skipType":"op","skipId":"bad","episodeLength":1420.1},
      {"interval":{"startTime":0.0,"endTime":30.0},"skipType":"preview","skipId":"unknown"}
    ],"message":"Successfully found skip times","statusCode":200}
    """

    func testQueriesNeverFallBackToSeasonOneTitle() {
        XCTAssertEqual(OnlineSkipClient.queries(title: "Naruto", slug: "naruto", season: 1), ["Naruto"])
        let s2 = OnlineSkipClient.queries(title: "Attack on Titan", slug: "attack-on-titan", season: 2)
        XCTAssertEqual(s2, ["Attack on Titan Season 2", "Attack on Titan 2"])
        let slugExtra = OnlineSkipClient.queries(title: "Shingeki no Kyojin", slug: "attack-on-titan", season: 1)
        XCTAssertEqual(slugExtra, ["Shingeki no Kyojin", "attack on titan"])
    }

    func testParseAniList() {
        XCTAssertEqual(OnlineSkipClient.parseAniList(status: 200, data: Data(#"{"data":{"Media":{"idMal":20}}}"#.utf8)), .found(20))
        XCTAssertEqual(OnlineSkipClient.parseAniList(status: 404, data: Data(#"{"data":{"Media":null}}"#.utf8)), .notFound)
        XCTAssertEqual(OnlineSkipClient.parseAniList(status: 200, data: Data(#"{"data":{"Media":{"idMal":null}}}"#.utf8)), .notFound)
        XCTAssertEqual(OnlineSkipClient.parseAniList(status: 429, data: Data()), .failed)
    }

    func testParseSkipTimesFiltersAndSorts() throws {
        let times = try XCTUnwrap(OnlineSkipClient.parseSkipTimes(status: 200, data: Data(skipJSON.utf8)))
        XCTAssertEqual(times.map(\.skipType), [.op, .ed])
        XCTAssertEqual(times.first?.interval.startTime, 60)
        XCTAssertEqual(times.first?.skipId, "aniskip-a")
        XCTAssertEqual(OnlineSkipClient.parseSkipTimes(status: 404, data: Data(#"{"found":false,"results":[]}"#.utf8)), [])
        XCTAssertNil(OnlineSkipClient.parseSkipTimes(status: 500, data: Data()))
    }

    func testEndToEndWithCaching() async {
        let http = FakeHTTP([
            aniList: FakeHTTP.ok(#"{"data":{"Media":{"idMal":20}}}"#),
            aniSkip(20, 3): FakeHTTP.ok(skipJSON),
        ])
        let client = OnlineSkipClient(transport: http)
        let first = await client.skipTimes(seriesTitle: "Naruto", seriesSlug: "naruto", season: 1, episode: 3)
        XCTAssertEqual(first.count, 2)
        let again = await client.skipTimes(seriesTitle: "Naruto", seriesSlug: "naruto", season: 1, episode: 3)
        XCTAssertEqual(again, first)
        XCTAssertEqual(http.requested.count, 2, "MAL id and skip times are cached")
    }

    /// Real AniSkip answer for Attack on Titan S2E1 vs. the aniworld stream (1450.133 s).
    func testAlignmentToStreamLength() {
        func t(_ type: SkipType, _ s: Double, _ e: Double, _ len: Double) -> SkipTime {
            SkipTime(skipId: type.rawValue, skipType: type, interval: SkipInterval(startTime: s, endTime: e), episodeLength: len)
        }
        let aniSkip = [
            t(.mixedOp, 0.5, 17.083, 1467.08),   // other version: dropped
            t(.recap, 18.248, 108.248, 1467.08), // other version: dropped
            t(.op, 167.705, 257.705, 1450.226),  // same version: kept as is
            t(.ed, 1430.034, 1461.0, 1461.971),  // 11.8 s longer version: shifted with the end
        ]
        let aligned = SkipTimeAlignment.align(aniSkip, toDuration: 1450.133)
        XCTAssertEqual(aligned.map(\.skipType), [.op, .ed])
        XCTAssertEqual(aligned[0].interval.startTime, 167.705)
        XCTAssertEqual(aligned[1].interval.startTime, 1430.034 - 11.838, accuracy: 0.01)
        XCTAssertLessThanOrEqual(aligned[1].interval.endTime, 1450.133)

        // Unknown duration or unknown episode length: untouched.
        XCTAssertEqual(SkipTimeAlignment.align(aniSkip, toDuration: 0), aniSkip)
        let custom = [t(.op, 60, 150, 0)]
        XCTAssertEqual(SkipTimeAlignment.align(custom, toDuration: 1400), custom)
        // An outro of a far longer version is dropped instead of guessed.
        XCTAssertEqual(SkipTimeAlignment.align([t(.ed, 1500, 1590, 1620)], toDuration: 1450), [])
    }

    func testFilmsAndOfflineYieldNothing() async {
        let http = FakeHTTP()
        let client = OnlineSkipClient(transport: http)
        let film = await client.skipTimes(seriesTitle: "Naruto", seriesSlug: "naruto", season: 0, episode: 1)
        XCTAssertEqual(film, [])
        XCTAssertTrue(http.requested.isEmpty)

        http.failAll = true
        let offline = await client.skipTimes(seriesTitle: "Naruto", seriesSlug: "naruto", season: 1, episode: 1)
        XCTAssertEqual(offline, [])
    }
}
