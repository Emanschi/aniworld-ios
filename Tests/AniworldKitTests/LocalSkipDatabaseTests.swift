import XCTest
@testable import AniworldKit

final class LocalSkipDatabaseTests: XCTestCase {
    func testRangeAndEpisodeResolution() {
        let jsonString = """
        {
          "attack-on-titan": {
            "1": {
              "1": {
                "op": null,
                "ed": { "start": 1320.0, "end": 1410.0 }
              },
              "2-13": {
                "op": { "start": 90.0, "end": 180.0 },
                "ed": { "start": 1350.0, "end": 1440.0 }
              },
              "14": {
                "recap": { "start": 0.0, "end": 90.0 },
                "op": { "start": 90.0, "end": 180.0 }
              }
            },
            "2": {
              "default": {
                "op": { "start": 167.7, "end": 257.7 },
                "ed": { "start": 1430.0, "end": 1461.0 }
              }
            }
          }
        }
        """

        let db = LocalSkipDatabase(jsonData: Data(jsonString.utf8))

        // Episode 1: Op is null (explicitly no intro), Ed exists
        let ep1 = db.findSkipTimes(seriesSlug: "attack-on-titan", seriesTitle: "Attack on Titan", season: 1, episode: 1)
        XCTAssertNotNil(ep1)
        XCTAssertFalse(ep1!.contains(where: { $0.skipType.isOpening }))
        XCTAssertTrue(ep1!.contains(where: { $0.skipType.isEnding }))

        // Episode 5: In range 2-13
        let ep5 = db.findSkipTimes(seriesSlug: "attack-on-titan", seriesTitle: "Attack on Titan", season: 1, episode: 5)
        XCTAssertNotNil(ep5)
        let ep5Op = ep5!.first(where: { $0.skipType.isOpening })
        XCTAssertNotNil(ep5Op)
        XCTAssertEqual(ep5Op?.interval.startTime, 90.0)
        XCTAssertEqual(ep5Op?.interval.endTime, 180.0)

        // Episode 14: Special recap + opening
        let ep14 = db.findSkipTimes(seriesSlug: "attack-on-titan", seriesTitle: "Attack on Titan", season: 1, episode: 14)
        XCTAssertNotNil(ep14)
        XCTAssertTrue(ep14!.contains(where: { $0.skipType.isRecap }))
        XCTAssertTrue(ep14!.contains(where: { $0.skipType.isOpening }))

        // Season 2 Episode 3: Default wildcard
        let s2e3 = db.findSkipTimes(seriesSlug: "attack-on-titan", seriesTitle: "Attack on Titan", season: 2, episode: 3)
        XCTAssertNotNil(s2e3)
        let s2Op = s2e3!.first(where: { $0.skipType.isOpening })
        XCTAssertEqual(s2Op?.interval.startTime, 167.7)

        // Unknown anime returns nil
        let unknown = db.findSkipTimes(seriesSlug: "unknown-anime", seriesTitle: "Unknown", season: 1, episode: 1)
        XCTAssertNil(unknown)
    }
}
