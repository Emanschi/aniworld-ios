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

    func testSeasonVariantFallbackResolution() {
        let jsonString = """
        {
          "jujutsu-kaisen": {
            "1": {
              "1": { "op": { "start": 54.7, "end": 145.1 } }
            }
          },
          "jujutsu-kaisen-2nd-season": {
            "1": {
              "1": { "op": { "start": 224.0, "end": 314.0 } }
            }
          }
        }
        """

        let db = LocalSkipDatabase(jsonData: Data(jsonString.utf8))

        // When queried as base slug with season 2, resolves to jujutsu-kaisen-2nd-season
        let s2 = db.findSkipTimes(seriesSlug: "jujutsu-kaisen", seriesTitle: "Jujutsu Kaisen", season: 2, episode: 1)
        XCTAssertNotNil(s2)
        XCTAssertEqual(s2?.first(where: { $0.skipType.isOpening })?.interval.startTime, 224.0)
    }

    func testBundledDatabaseIntegrity() throws {
        let thisFile = URL(fileURLWithPath: #filePath)
        let repoRoot = thisFile.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let dbURL = repoRoot.appendingPathComponent("App/Resources/skip_database.json")
        guard FileManager.default.fileExists(atPath: dbURL.path) else {
            throw XCTSkip("Bundled database not found at \(dbURL.path)")
        }
        let data = try Data(contentsOf: dbURL)
        let db = LocalSkipDatabase(jsonData: data)

        // Test Attack on Titan Season 2
        let aotS2 = db.findSkipTimes(seriesSlug: "attack-on-titan", seriesTitle: "Attack on Titan", season: 2, episode: 1)
        XCTAssertNotNil(aotS2)
        XCTAssertEqual(aotS2?.first(where: { $0.skipType.isOpening })?.interval.startTime, 167.7)

        // Test One Piece Episode 100
        let op100 = db.findSkipTimes(seriesSlug: "one-piece", seriesTitle: "One Piece", season: 1, episode: 100)
        XCTAssertNotNil(op100)
        XCTAssertEqual(op100?.first(where: { $0.skipType.isOpening })?.interval.startTime, 1.0)

        // Test One Piece Episode 300
        let op300 = db.findSkipTimes(seriesSlug: "one-piece", seriesTitle: "One Piece", season: 1, episode: 300)
        XCTAssertNotNil(op300)
        XCTAssertEqual(op300?.first(where: { $0.skipType.isOpening })?.interval.startTime, 14.9)

        // Test Naruto Shippuden Episode 25
        let ns25 = db.findSkipTimes(seriesSlug: "naruto-shippuden", seriesTitle: "Naruto: Shippuden", season: 1, episode: 25)
        XCTAssertNotNil(ns25)
        XCTAssertEqual(ns25?.first(where: { $0.skipType.isOpening })?.interval.startTime, 336.0)

        // Test Death Note Episode 1 (Opening starts at 3m46s after Shinigami realm prologue)
        let dn1 = db.findSkipTimes(seriesSlug: "death-note", seriesTitle: "Death Note", season: 1, episode: 1)
        XCTAssertNotNil(dn1)
        XCTAssertEqual(dn1?.first(where: { $0.skipType.isOpening })?.interval.startTime, 226.0)

        // Test Death Note Episode 5 (Standard opening at 1m35s after cold open)
        let dn5 = db.findSkipTimes(seriesSlug: "death-note", seriesTitle: "Death Note", season: 1, episode: 5)
        XCTAssertNotNil(dn5)
        XCTAssertEqual(dn5?.first(where: { $0.skipType.isOpening })?.interval.startTime, 95.0)
    }
}
