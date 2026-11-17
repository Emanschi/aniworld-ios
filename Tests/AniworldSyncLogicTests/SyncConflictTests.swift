import XCTest
import AniworldKit
@testable import AniworldSyncLogic

final class SyncConflictTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private func t(_ offset: TimeInterval) -> Date { now.addingTimeInterval(offset) }
    private let url = URL(string: "https://example.org/x")!

    private func series(_ slug: String) -> SeriesSummary { SeriesSummary(slug: slug, title: slug, url: url) }
    private func fav(_ slug: String, _ at: Date) -> FavoriteEntry { FavoriteEntry(series: series(slug), addedAt: at) }
    private func watch(_ slug: String, _ at: Date) -> WatchEntry {
        WatchEntry(series: series(slug), episode: EpisodeRef(seriesSlug: slug, season: 1, number: 1, url: url),
                   language: nil, position: 100, duration: 1400, updatedAt: at, isFinished: false)
    }
    private func snapshot(_ id: String, _ state: LibraryState, stats: StatsState = StatsState()) -> SyncSnapshot {
        SyncSnapshot(deviceID: id, deviceName: "Gerät \(id)", writtenAt: now, state: state, stats: stats)
    }
    private func plan(_ local: LibraryState, _ remote: [SyncSnapshot]) -> SyncPlan {
        SyncPlanner.plan(local: local, localStats: StatsState(), localDeviceName: "Ich", remote: remote, now: now)
    }

    func testPurelyAdditiveMergeNeedsNoDecision() {
        let local = LibraryState(favorites: [fav("a", t(-100))])
        let remote = LibraryState(favorites: [fav("b", t(-50))], history: [watch("b", t(-50))])
        let p = plan(local, [snapshot("R", remote)])
        XCTAssertFalse(p.needsDecision)
        XCTAssertEqual(p.merged.favorites.count, 2)
    }

    func testRemoteResetWipingLocalDataNeedsDecision() {
        var local = LibraryState(favorites: [fav("a", t(-100))], history: [watch("a", t(-100))])
        local.progress["a-s1e1"] = EpisodeProgress(position: 900, duration: 1400, watched: false, updatedAt: t(-100))
        let remote = LibraryState(resetAt: t(-10))
        let p = plan(local, [snapshot("R", remote)])
        XCTAssertTrue(p.needsDecision)
        XCTAssertTrue(p.reasons.contains(.remoteReset))
        XCTAssertEqual(p.losses.favorites, 1)
        XCTAssertEqual(p.losses.history, 1)
        XCTAssertEqual(p.losses.progressRemoved, 1)
        XCTAssertEqual(p.local.favorites, 1)
        XCTAssertEqual(p.remote.deviceName, "Gerät R")
    }

    func testRemoteTombstoneAndClockSkewAreDetected() {
        let local = LibraryState(favorites: [fav("a", t(-100))])
        // Remote device with a clock far in the future removed "a".
        let remote = LibraryState(favoriteTombstones: ["a": t(86_400 * 30)])
        let p = plan(local, [snapshot("R", remote)])
        XCTAssertEqual(p.losses.favorites, 1)
        XCTAssertTrue(p.needsDecision)
        XCTAssertTrue(p.reasons.contains(.futureTimestamp))
    }

    func testProgressBackwardsAndUnwatchedAreDetected() {
        var local = LibraryState()
        local.progress["a-s1e1"] = EpisodeProgress(position: 1400, duration: 1400, watched: true, updatedAt: t(-100))
        local.progress["a-s1e2"] = EpisodeProgress(position: 800, duration: 1400, watched: false, updatedAt: t(-100))
        local.progress["a-s1e3"] = EpisodeProgress(position: 800, duration: 1400, watched: false, updatedAt: t(-100))
        var remote = LibraryState()
        remote.progress["a-s1e1"] = EpisodeProgress(position: 0, duration: 1400, watched: false, updatedAt: t(-10))
        remote.progress["a-s1e2"] = EpisodeProgress(position: 100, duration: 1400, watched: false, updatedAt: t(-10))
        remote.progress["a-s1e3"] = EpisodeProgress(position: 770, duration: 1400, watched: false, updatedAt: t(-10))
        let p = plan(local, [snapshot("R", remote)])
        XCTAssertEqual(p.losses.progressBackwards, 2) // e3 is within the tolerance
        XCTAssertFalse(p.needsDecision) // a few newer remote progress records are applied silently
        XCTAssertEqual(p.losses.progressRemoved, 0)
    }

    func testRemovedCustomSkipIsDetected() {
        let skip = CustomSkip(seriesSlug: "a", season: 1, episode: nil, introStart: 5, introEnd: 80,
                              outroStart: nil, outroEnd: nil, updatedAt: t(-100))
        let local = LibraryState(customSkips: [skip])
        let remote = LibraryState(customSkipTombstones: [skip.key: t(-10)])
        let p = plan(local, [snapshot("R", remote)])
        XCTAssertEqual(p.losses.customSkips, 1)
        XCTAssertFalse(p.needsDecision)
    }

    // MARK: Silent vs. asking

    func testSingleRemoteFavoriteRemovalIsSilent() {
        let local = LibraryState(favorites: [fav("a", t(-100)), fav("b", t(-100))])
        let remote = LibraryState(favoriteTombstones: ["a": t(-10)])
        let p = plan(local, [snapshot("R", remote)])
        XCTAssertEqual(p.losses.favorites, 1)
        XCTAssertFalse(p.needsDecision)
        XCTAssertEqual(p.merged.favorites.map { $0.id }, ["b"])
    }

    func testSingleHistoryRemovalAndSmallProgressChangeAreSilent() {
        var local = LibraryState(favorites: [fav("x", t(-100))], history: [watch("a", t(-100))])
        local.progress["a-s1e1"] = EpisodeProgress(position: 1400, duration: 1400, watched: true, updatedAt: t(-100))
        var remote = LibraryState(historyTombstones: ["a": t(-10)])
        remote.progress["a-s1e1"] = EpisodeProgress(position: 0, duration: 1400, watched: false, updatedAt: t(-10))
        let p = plan(local, [snapshot("R", remote)])
        XCTAssertEqual(p.losses.history, 1)
        XCTAssertEqual(p.losses.progressBackwards, 1)
        XCTAssertFalse(p.needsDecision)
    }

    func testTombstoneWithinClockToleranceIsSilentButFarFutureAsks() {
        let local = LibraryState(favorites: [fav("a", t(-100)), fav("b", t(-100))])
        let near = LibraryState(favoriteTombstones: ["a": t(60)])
        XCTAssertFalse(plan(local, [snapshot("R", near)]).needsDecision)
        let far = LibraryState(favoriteTombstones: ["a": t(600)])
        let p = plan(local, [snapshot("R", far)])
        XCTAssertTrue(p.needsDecision)
        XCTAssertTrue(p.reasons.contains(.futureTimestamp))
    }

    func testFutureResetAsksEvenWhenItRemovesNothingLocally() {
        let local = LibraryState(favorites: [fav("a", t(-100)), fav("b", t(-100))],
                                 history: [watch("a", t(-100))])
        // Remote tombstone silently removes "a", but a future historyClearedAt is also present.
        let remote = LibraryState(favoriteTombstones: ["a": t(-10)], historyClearedAt: t(86_400))
        let p = plan(local, [snapshot("R", remote)])
        XCTAssertTrue(p.needsDecision)
        XCTAssertTrue(p.reasons.contains(.futureTimestamp))
    }

    func testHistoryClearedAsks() {
        let local = LibraryState(favorites: [fav("x", t(-100))], history: [watch("a", t(-100))])
        let remote = LibraryState(historyClearedAt: t(-10))
        let p = plan(local, [snapshot("R", remote)])
        XCTAssertTrue(p.needsDecision)
        XCTAssertEqual(p.reasons, [.historyCleared])
    }

    func testRemoteResetAsksWithReason() {
        let local = LibraryState(favorites: [fav("a", t(-100)), fav("b", t(-100))])
        let p = plan(local, [snapshot("R", LibraryState(resetAt: t(-10)))])
        XCTAssertTrue(p.reasons.contains(.remoteReset))
    }

    func testManyFavoriteRemovalsAsk() {
        let favs = (0..<SyncPlanner.favoritesThreshold + 2).map { fav("f\($0)", t(-100)) }
        var tombs: [String: Date] = [:]
        for f in favs.prefix(SyncPlanner.favoritesThreshold) { tombs[f.id] = t(-10) }
        let p = plan(LibraryState(favorites: favs), [snapshot("R", LibraryState(favoriteTombstones: tombs))])
        XCTAssertTrue(p.needsDecision)
        XCTAssertEqual(p.reasons, [.tooMany("Favoriten", SyncPlanner.favoritesThreshold)])
    }

    func testManyCustomSkipRemovalsAsk() {
        let skips = (0..<SyncPlanner.customSkipsThreshold + 1).map {
            CustomSkip(seriesSlug: "s\($0)", season: 1, episode: nil, introStart: 5, introEnd: 80,
                       outroStart: nil, outroEnd: nil, updatedAt: t(-100))
        }
        var tombs: [String: Date] = [:]
        for s in skips.prefix(SyncPlanner.customSkipsThreshold) { tombs[s.key] = t(-10) }
        let p = plan(LibraryState(favorites: [fav("k", t(-1))], customSkips: skips),
                     [snapshot("R", LibraryState(customSkipTombstones: tombs))])
        XCTAssertTrue(p.needsDecision)
    }

    func testManyProgressRegressionsAsk() {
        var local = LibraryState(favorites: [fav("k", t(-1))])
        var remote = LibraryState()
        for i in 0..<SyncPlanner.progressThreshold {
            local.progress["a-s1e\(i)"] = EpisodeProgress(position: 1400, duration: 1400, watched: true, updatedAt: t(-100))
            remote.progress["a-s1e\(i)"] = EpisodeProgress(position: 0, duration: 1400, watched: false, updatedAt: t(-10))
        }
        let p = plan(local, [snapshot("R", remote)])
        XCTAssertEqual(p.losses.progressBackwards, SyncPlanner.progressThreshold)
        XCTAssertTrue(p.needsDecision)
    }

    func testWipingSmallLocalLibraryEntirelyAsks() {
        let local = LibraryState(favorites: [fav("a", t(-100)), fav("b", t(-100)), fav("c", t(-100))])
        let remote = LibraryState(favoriteTombstones: ["a": t(-10), "b": t(-10), "c": t(-10)])
        let p = plan(local, [snapshot("R", remote)])
        XCTAssertEqual(p.reasons, [.wholesale])
    }

    func testStatsResetAsks() {
        let s = WatchSession(id: "s1", seriesSlug: "a", seriesTitle: "A", season: 1, episode: 1, language: nil,
                             hoster: "VOE", startedAt: t(-5000), endedAt: t(-3800), watchedSeconds: 1200,
                             episodeDuration: 1400, completed: true, skippedSeconds: 0, wasOffline: false,
                             deviceID: "L")
        let p = SyncPlanner.plan(local: LibraryState(), localStats: StatsState(sessions: [s]),
                                 localDeviceName: "Ich",
                                 remote: [snapshot("R", LibraryState(), stats: StatsState(resetAt: t(-10)))], now: now)
        XCTAssertTrue(p.reasons.contains(.statsReset))
    }

    func testDroppedStatsSessionsAreDetected() {
        let s = WatchSession(id: "s1", seriesSlug: "a", seriesTitle: "A", season: 1, episode: 1, language: nil,
                             hoster: "VOE", startedAt: t(-5000), endedAt: t(-3800), watchedSeconds: 1200,
                             episodeDuration: 1400, completed: true, skippedSeconds: 0, wasOffline: false,
                             deviceID: "L")
        let remote = snapshot("R", LibraryState(), stats: StatsState(resetAt: t(-10)))
        let p = SyncPlanner.plan(local: LibraryState(), localStats: StatsState(sessions: [s]),
                                 localDeviceName: "Ich", remote: [remote], now: now)
        XCTAssertEqual(p.losses.statsSessions, 1)
    }

    func testAssertLocalSurvivesRemoteResetTombstonesAndKeepsOrder() {
        let local = LibraryState(favorites: [fav("b", t(-10)), fav("a", t(-100))],
                                 history: [watch("b", t(-10)), watch("a", t(-100))])
        let remote = LibraryState(favoriteTombstones: ["a": t(-5)], resetAt: t(-1),
                                  customSkipTombstones: ["x": t(3600)])
        let auth = SyncPlanner.assertLocal(local, over: [remote], now: now)
        let merged = LibraryMerge.merge([auth, remote], now: now)
        XCTAssertEqual(merged.favorites.map { $0.id }, ["b", "a"])
        XCTAssertEqual(merged.history.map { $0.id }, ["b", "a"])
        // The other side drops its own older data and adopts the authoritative state.
        let theirs = LibraryState(favorites: [fav("old", t(-500))], resetAt: t(-1))
        let there = LibraryMerge.merge([theirs, auth], now: now)
        XCTAssertEqual(Set(there.favorites.map { $0.id }), ["a", "b"])
        // No further decision needed on the keeper afterwards.
        XCTAssertTrue(plan(auth, [snapshot("R", remote)]).losses.isEmpty)
    }

    func testAssertLocalBeatsFutureSkewedReset() {
        let local = LibraryState(favorites: [fav("a", t(-100))])
        let remote = LibraryState(resetAt: t(86_400 * 10))
        let auth = SyncPlanner.assertLocal(local, over: [remote], now: now)
        XCTAssertGreaterThan(auth.resetAt!, remote.resetAt!)
        XCTAssertEqual(LibraryMerge.merge([auth, remote], now: now).favorites.count, 1)
    }

    func testAdoptRemoteReplacesLocal() {
        let remote = LibraryState(favorites: [fav("b", t(-50))])
        let adopted = SyncPlanner.adoptRemote(remote: [snapshot("R", remote)], localStats: StatsState(), now: now)
        XCTAssertEqual(adopted.library.favorites.map { $0.id }, ["b"])
    }

    func testSnapshotKeepsSchemaVersionAndOldFilesDecode() throws {
        XCTAssertEqual(SyncSnapshot.currentSchemaVersion, 1)
        let json = Data(#"{"schemaVersion":1,"deviceID":"X"}"#.utf8)
        let snap = try JSONDecoder().decode(SyncSnapshot.self, from: json)
        XCTAssertNil(snap.statsRestoredAt)
        XCTAssertTrue(snap.favorites.isEmpty)
    }

    func testBackupsRoundTripAndKeepFive() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("backup-test-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = LibraryBackupStore(directory: dir)
        for i in 0..<8 {
            let state = LibraryState(favorites: [fav("s\(i)", t(Double(i)))])
            try store.write(LibraryBackup(createdAt: t(Double(i)), reason: "t", library: state, stats: StatsState()))
        }
        XCTAssertEqual(store.files().count, LibraryBackupStore.keepCount)
        XCTAssertEqual(store.latest()?.library.favorites.first?.id, "s7")
        // Same second twice: both are kept, the later one is the newest.
        try store.write(LibraryBackup(createdAt: t(7), reason: "again", library: LibraryState(), stats: StatsState()))
        XCTAssertEqual(store.latest()?.reason, "again")
    }
}
