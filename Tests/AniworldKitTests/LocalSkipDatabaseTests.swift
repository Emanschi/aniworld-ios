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

    func testOverlappingRangesNarrowestWins() {
        let json = """
        { "show": { "1": {
          "1-100": { "op": { "start": 10.0, "end": 20.0 } },
          "50-60": { "op": { "start": 30.0, "end": 40.0 } },
          "55": { "op": { "start": 50.0, "end": 60.0 } },
          "*": { "op": { "start": 70.0, "end": 80.0 } }
        } } }
        """
        let db = LocalSkipDatabase(jsonData: Data(json.utf8))
        func opStart(_ ep: Int) -> Double? {
            db.findSkipTimes(seriesSlug: "show", seriesTitle: "Show", season: 1, episode: ep)?
                .first(where: { $0.skipType.isOpening })?.interval.startTime
        }
        XCTAssertEqual(opStart(55), 50.0)   // single beats range
        XCTAssertEqual(opStart(52), 30.0)   // narrower range beats wider range
        XCTAssertEqual(opStart(10), 10.0)   // only the wide range matches
        XCTAssertEqual(opStart(500), 70.0)  // wildcard last
    }

    func testSeasonAliasBeatsBaseDefault() {
        let json = """
        {
          "jujutsu-kaisen": {
            "1": { "1": { "op": { "start": 54.7, "end": 145.1 } } },
            "default": { "*": { "op": { "start": 1.0, "end": 2.0 } } }
          },
          "jujutsu-kaisen-2nd-season": {
            "1": { "1": { "op": { "start": 224.0, "end": 314.0 } } }
          }
        }
        """
        let db = LocalSkipDatabase(jsonData: Data(json.utf8))
        func opStart(season: Int, episode: Int) -> Double? {
            db.findSkipTimes(seriesSlug: "jujutsu-kaisen", seriesTitle: "Jujutsu Kaisen", season: season, episode: episode)?
                .first(where: { $0.skipType.isOpening })?.interval.startTime
        }
        XCTAssertEqual(opStart(season: 2, episode: 1), 224.0)   // alias wins over base default
        XCTAssertEqual(opStart(season: 2, episode: 5), 1.0)     // alias has no episode 5 -> base default
        XCTAssertEqual(opStart(season: 3, episode: 1), 1.0)     // no alias for season 3 -> base default
        XCTAssertEqual(opStart(season: 1, episode: 1), 54.7)    // exact season first
    }

    func testExactSeasonBeatsAliasAndDefault() {
        let json = """
        {
          "show": {
            "2": { "1": { "op": { "start": 5.0, "end": 9.0 } } },
            "default": { "*": { "op": { "start": 1.0, "end": 2.0 } } }
          },
          "show-2nd-season": { "1": { "1": { "op": { "start": 100.0, "end": 200.0 } } } }
        }
        """
        let db = LocalSkipDatabase(jsonData: Data(json.utf8))
        let times = db.findSkipTimes(seriesSlug: "show", seriesTitle: "Show", season: 2, episode: 1)
        XCTAssertEqual(times?.first(where: { $0.skipType.isOpening })?.interval.startTime, 5.0)
    }

    func testEmptyNormalizedKeysNeverMatch() {
        let json = """
        {
          "進撃の巨人": { "default": { "*": { "op": { "start": 1.0, "end": 2.0 } } } },
          "": { "default": { "*": { "op": { "start": 3.0, "end": 4.0 } } } }
        }
        """
        let db = LocalSkipDatabase(jsonData: Data(json.utf8))
        XCTAssertNil(db.findSkipTimes(seriesSlug: "", seriesTitle: "進撃の巨人", season: 1, episode: 1))
        XCTAssertNil(db.findSkipTimes(seriesSlug: "", seriesTitle: "", season: 2, episode: 1))
        XCTAssertNil(db.findSkipTimes(seriesSlug: "!!!", seriesTitle: "???", season: 1, episode: 1))
    }

    func testEpisodePatternPrefixes() {
        let json = """
        { "show": { "1": {
          "folge 1": { "op": { "start": 1.0, "end": 2.0 } },
          "ep2": { "op": { "start": 3.0, "end": 4.0 } },
          "Episode 3-4": { "op": { "start": 5.0, "end": 6.0 } },
          "e5": { "op": { "start": 7.0, "end": 8.0 } },
          "deep": { "op": { "start": 9.0, "end": 10.0 } }
        } } }
        """
        let db = LocalSkipDatabase(jsonData: Data(json.utf8))
        func opStart(_ ep: Int) -> Double? {
            db.findSkipTimes(seriesSlug: "show", seriesTitle: "Show", season: 1, episode: ep)?
                .first(where: { $0.skipType.isOpening })?.interval.startTime
        }
        XCTAssertEqual(opStart(1), 1.0)
        XCTAssertEqual(opStart(2), 3.0)
        XCTAssertEqual(opStart(4), 5.0)
        XCTAssertEqual(opStart(5), 7.0)
        XCTAssertNil(opStart(6))
    }

    /// The bundled database is optional in the repo; if present it must parse and contain data.
    func testBundledDatabaseIntegrity() throws {
        let thisFile = URL(fileURLWithPath: #filePath)
        let repoRoot = thisFile.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let dbURL = repoRoot.appendingPathComponent("App/Resources/skip_database.json")
        guard FileManager.default.fileExists(atPath: dbURL.path) else {
            throw XCTSkip("Bundled database not found at \(dbURL.path)")
        }
        let data = try Data(contentsOf: dbURL)
        let object = try JSONSerialization.jsonObject(with: data)
        let dict = try XCTUnwrap(object as? [String: Any], "skip_database.json must be a JSON object")
        XCTAssertFalse(dict.isEmpty)
    }
}