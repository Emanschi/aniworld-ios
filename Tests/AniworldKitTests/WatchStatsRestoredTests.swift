import XCTest
@testable import AniworldKit

final class WatchStatsRestoredTests: XCTestCase {
    private func session(_ id: String, end: Date, device: String) -> WatchSession {
        WatchSession(id: id, seriesSlug: "naruto", seriesTitle: "Naruto", season: 1, episode: 1,
                     language: nil, hoster: "VOE", startedAt: end.addingTimeInterval(-1200), endedAt: end,
                     watchedSeconds: 1200, episodeDuration: 1400, completed: true, skippedSeconds: 0,
                     wasOffline: false, deviceID: device)
    }

    func testRestoredStateSurvivesNewerResetOfOtherDevice() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let mine = session("mine", end: now.addingTimeInterval(-5000), device: "A")
        let theirs = session("theirs", end: now.addingTimeInterval(-6000), device: "B")
        let reset = now.addingTimeInterval(-100)
        let a = StatsState(sessions: [mine], resetAt: nil, restoredAt: now)
        let b = StatsState(sessions: [theirs], resetAt: reset)
        let merged = StatsMerge.merge([a, b], now: now)
        XCTAssertEqual(merged.sessions.map { $0.id }, ["mine"])
        XCTAssertEqual(merged.resetAt, reset)
        XCTAssertEqual(StatsMerge.merge([b, a], now: now), merged)
        XCTAssertEqual(StatsMerge.merge([merged, a], now: now), merged)
        // A newer reset cancels the exemption again.
        let later = StatsState(sessions: [], resetAt: now.addingTimeInterval(10))
        XCTAssertTrue(StatsMerge.merge([a, later], now: now).sessions.isEmpty)
    }
}
