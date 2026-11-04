import XCTest
@testable import AniworldKit

final class PlaceholderTests: XCTestCase {
    func testModelCode() {
        let ep = EpisodeRef(seriesSlug: "naruto", season: 1, number: 3, url: URL(string: "https://aniworld.to")!)
        XCTAssertEqual(ep.code, "S01E03")
    }
}
