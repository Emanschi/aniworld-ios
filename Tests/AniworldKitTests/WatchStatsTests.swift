import XCTest
@testable import AniworldKit

final class WatchStatsTests: XCTestCase {
    private var calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()

    private func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 12, _ min: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))!
    }

    private func session(_ id: String, slug: String = "naruto", ep: Int = 1, start: Date, minutes: Double = 20,
                         lang: StreamLanguage? = .germanDub, completed: Bool = true, skipped: Double = 0,
                         offline: Bool = false, device: String = "A") -> WatchSession {
        WatchSession(id: id, seriesSlug: slug, seriesTitle: slug.capitalized, season: 1, episode: ep,
                     language: lang, hoster: "VOE", startedAt: start,
                     endedAt: start.addingTimeInterval(minutes * 60), watchedSeconds: minutes * 60,
                     episodeDuration: 1400, completed: completed, skippedSeconds: skipped,
                     wasOffline: offline, deviceID: device)
    }

    // MARK: Streak

    func testStreakCountsOnlyCompletedEpisodes() {
        let now = date(2026, 11, 10, 9)
        let sessions = [
            session("a", start: date(2026, 11, 7)),
            session("b", start: date(2026, 11, 8)),
            session("c", start: date(2026, 11, 9)),
            session("partial", start: date(2026, 11, 10, 8), minutes: 5, completed: false),
        ]
        let streak = WatchStreak.compute(sessions: sessions, now: now, calendar: calendar)
        XCTAssertEqual(streak.current, 3)
        XCTAssertFalse(streak.todayDone)
        XCTAssertTrue(streak.atRisk)
        XCTAssertEqual(streak.lastSevenDays.count, 7)
        XCTAssertEqual(streak.lastSevenDays.map { $0.done }, [false, false, false, true, true, true, false])
    }

    func testStreakBreaksAfterMissedDayAndKeepsLongest() {
        let now = date(2026, 11, 10)
        let sessions = [
            session("a", start: date(2026, 11, 1)),
            session("b", start: date(2026, 11, 2)),
            session("c", start: date(2026, 11, 3)),
            session("d", start: date(2026, 11, 3, 20)),
            session("e", start: date(2026, 11, 10, 8)),
        ]
        let streak = WatchStreak.compute(sessions: sessions, now: now, calendar: calendar)
        XCTAssertEqual(streak.current, 1)
        XCTAssertTrue(streak.todayDone)
        XCTAssertFalse(streak.atRisk)
        XCTAssertEqual(streak.longest, 3)
        XCTAssertEqual(WatchStreak.compute(sessions: [], now: now, calendar: calendar).current, 0)
    }

    // MARK: Merge

    func testMergeUnionAndNewerEndWins() {
        let now = date(2026, 11, 5)
        let a = session("1", start: date(2026, 11, 1), minutes: 10)
        var a2 = a
        a2.endedAt = a.endedAt.addingTimeInterval(600)
        a2.watchedSeconds += 600
        let b = session("2", slug: "bleach", start: date(2026, 11, 2), device: "B")
        let merged = StatsMerge.merge([StatsState(sessions: [a, b]), StatsState(sessions: [a2])], now: now)
        XCTAssertEqual(merged.sessions.map { $0.id }, ["1", "2"])
        XCTAssertEqual(merged.sessions[0].watchedSeconds, a2.watchedSeconds)
        // commutative + idempotent
        let swapped = StatsMerge.merge([StatsState(sessions: [a2]), StatsState(sessions: [b, a])], now: now)
        XCTAssertEqual(merged, swapped)
        XCTAssertEqual(StatsMerge.merge([merged, StatsState(sessions: [a])], now: now), merged)
    }

    func testResetDropsOldSessionsEverywhere() {
        let now = date(2026, 11, 5)
        let old = session("1", start: date(2026, 11, 1))
        let fresh = session("2", slug: "bleach", start: date(2026, 11, 4), device: "B")
        let reset = date(2026, 11, 3)
        let merged = StatsMerge.merge([StatsState(sessions: [], resetAt: reset),
                                       StatsState(sessions: [old, fresh])], now: now)
        XCTAssertEqual(merged.sessions.map { $0.id }, ["2"])
        XCTAssertEqual(merged.resetAt, reset)
    }

    func testRetentionDropsVeryOldSessions() {
        let now = date(2026, 11, 5)
        let ancient = session("old", start: date(2023, 1, 1))
        let merged = StatsMerge.merge([StatsState(sessions: [ancient])], now: now)
        XCTAssertTrue(merged.sessions.isEmpty)
    }

    func testOldSnapshotWithoutFieldsDecodes() throws {
        let json = #"{"id":"x","slug":"naruto","start":1000}"#
        let s = try JSONDecoder().decode(WatchSession.self, from: Data(json.utf8))
        XCTAssertEqual(s.seriesTitle, "naruto")
        XCTAssertEqual(s.watchedSeconds, 0)
        let state = try JSONDecoder().decode(StatsState.self, from: Data(#"{"sessions":[],"seriesMeta":{}}"#.utf8))
        XCTAssertNil(state.resetAt)
    }

    func testSessionRoundTrip() throws {
        let s = session("1", start: date(2026, 11, 1))
        let data = try JSONEncoder().encode(s)
        XCTAssertEqual(try JSONDecoder().decode(WatchSession.self, from: data), s)
    }

    // MARK: Calculator

    func testEmptyData() {
        let p = StatsPeriod.month(year: 2026, month: 10)
        let stats = WatchStatsCalculator(sessions: [], interval: p.interval(calendar: calendar), calendar: calendar).compute()
        XCTAssertFalse(stats.hasData)
        XCTAssertEqual(stats.totalSeconds, 0)
        XCTAssertNil(stats.funComparison)
    }

    func testBasicNumbers() {
        let sessions = [
            session("1", slug: "naruto", ep: 1, start: date(2026, 10, 1, 20, 0), minutes: 20, lang: .germanDub, skipped: 90),
            session("2", slug: "naruto", ep: 2, start: date(2026, 10, 1, 20, 25), minutes: 20, lang: .germanDub, skipped: 90),
            session("3", slug: "bleach", ep: 1, start: date(2026, 10, 2, 9, 0), minutes: 10, lang: .englishSub, completed: false, offline: true),
            session("4", slug: "bleach", ep: 1, start: date(2026, 9, 20, 9, 0), minutes: 30),
        ]
        let p = StatsPeriod.month(year: 2026, month: 10)
        let meta = ["naruto": SeriesMeta(genres: ["Action", "Abenteuer"], ageRating: 12, updatedAt: date(2026, 10, 1))]
        let stats = WatchStatsCalculator(sessions: sessions, interval: p.interval(calendar: calendar), calendar: calendar,
                                         seriesMeta: meta, previousInterval: p.previousInterval(calendar: calendar)).compute()
        XCTAssertTrue(stats.hasData)
        XCTAssertEqual(stats.totalSeconds, 50 * 60)
        XCTAssertEqual(stats.episodeCount, 3)
        XCTAssertEqual(stats.completedEpisodeCount, 2)
        XCTAssertEqual(stats.seriesCount, 2)
        XCTAssertEqual(stats.topSeries.first?.slug, "naruto")
        XCTAssertEqual(stats.topSeries.first?.share ?? 0, 0.8, accuracy: 0.001)
        XCTAssertEqual(stats.topGenres.count, 2)
        XCTAssertEqual(stats.topGenres.first?.share ?? 0, 0.5, accuracy: 0.001)
        XCTAssertEqual(stats.languages.map { $0.name }, ["GerDub", "EngSub"])
        XCTAssertEqual(stats.activeDays, 2)
        XCTAssertEqual(stats.skippedSeconds, 180)
        XCTAssertEqual(stats.offlineShare, 0.2, accuracy: 0.001)
        XCTAssertEqual(stats.newSeriesCount, 1) // naruto; bleach started in September
        XCTAssertEqual(stats.longestBinge?.episodes, 2)
        XCTAssertEqual(stats.longestStreakDays, 2)
        XCTAssertEqual(stats.previousTotalSeconds, 30 * 60)
        XCTAssertEqual(stats.changeToPrevious ?? 0, (50.0 - 30.0) / 30.0, accuracy: 0.001)
        XCTAssertEqual(stats.mostActiveTimeOfDay, .evening)
        // 1 Oct 2026 is a Thursday → index 3
        XCTAssertEqual(stats.mostActiveWeekday, 3)
    }

    func testStreakAndGaps() {
        let s = [
            session("1", ep: 1, start: date(2026, 10, 1)),
            session("2", ep: 2, start: date(2026, 10, 2)),
            session("3", ep: 3, start: date(2026, 10, 3)),
            session("4", ep: 4, start: date(2026, 10, 10)),
        ]
        let p = StatsPeriod.month(year: 2026, month: 10)
        let stats = WatchStatsCalculator(sessions: s, interval: p.interval(calendar: calendar), calendar: calendar).compute()
        XCTAssertEqual(stats.longestStreakDays, 3)
        XCTAssertEqual(stats.longestBinge?.episodes, 1)
    }

    func testPeriods() {
        let now = date(2026, 11, 5)
        XCTAssertEqual(StatsPeriod.previousMonth(of: now, calendar: calendar), .month(year: 2026, month: 10))
        XCTAssertEqual(StatsPeriod.previousMonth(of: date(2026, 1, 3), calendar: calendar), .month(year: 2025, month: 12))
        let months = StatsPeriod.availableMonths(firstDate: date(2026, 8, 15), now: now, calendar: calendar)
        XCTAssertEqual(months, [.month(year: 2026, month: 11), .month(year: 2026, month: 10),
                                .month(year: 2026, month: 9), .month(year: 2026, month: 8)])
        XCTAssertEqual(StatsPeriod.month(year: 2026, month: 10).title, "Oktober 2026")
    }

    func testFunComparison() {
        XCTAssertNil(WatchStatsCalculator.funComparison(totalSeconds: 600))
        XCTAssertEqual(WatchStatsCalculator.funComparison(totalSeconds: 3 * 3600), "Das entspricht einem Film à 2 Stunden.")
        XCTAssertEqual(WatchStatsCalculator.funComparison(totalSeconds: 6 * 3600), "Das entspricht 3 Filmen à 2 Stunden.")
        XCTAssertEqual(WatchStatsCalculator.funComparison(totalSeconds: 30 * 3600)?.contains("Herr-der-Ringe"), true)
    }
}
