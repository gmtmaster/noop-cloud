import XCTest
import Foundation
import WhoopStore
import StrandAnalytics
@testable import Strand

/// A finalized wake-day session and its sleep-only Rest projection are first-class UI facts even before
/// canonical daily analysis creates that day's DailyMetric.
final class SleepSessionVisibilityTests: XCTestCase {
    private let budapest = TimeZone(identifier: "Europe/Budapest")!

    private func ts(_ iso: String) -> Int {
        Int(ISO8601DateFormatter().date(from: iso)!.timeIntervalSince1970)
    }

    private func session(_ start: String, _ end: String, edited: Bool = false) -> CachedSleepSession {
        CachedSleepSession(startTs: ts(start), endTs: ts(end), efficiency: 0.88,
                           restingHr: 49, avgHrv: 71,
                           stagesJSON: #"[{"start":0,"end":1800,"stage":"light"}]"#,
                           userEdited: edited)
    }

    func testAug8ScoredNightRemainsScoredAndAug9SessionOnlyNightIsVisibleEverywhere() {
        let aug8 = session("2026-08-07T21:30:00Z", "2026-08-08T06:00:00Z")
        let aug9 = session("2026-08-09T01:27:14Z", "2026-08-09T09:07:34Z")
        let rows = [aug8, aug9]

        XCTAssertEqual(Repository.sleepWakeDayKey(aug8, timeZone: budapest), "2026-08-08")
        XCTAssertEqual(Repository.sleepWakeDayKey(aug9, timeZone: budapest), "2026-08-09")
        XCTAssertEqual(Repository.sleepSession(forWakeDay: "2026-08-08", in: rows,
                                               timeZone: budapest), aug8)
        XCTAssertEqual(Repository.sleepSession(forWakeDay: "2026-08-09", in: rows,
                                               timeZone: budapest), aug9)

        // Existing Aug 8 daily Rest behavior is unchanged.
        XCTAssertEqual(TodayView.restScoreForWakeDay(
            todayValue: 82, lastDay: "2026-08-08", lastValue: 82,
            isTodaySelected: false, todayKey: "2026-08-08", hasFinalizedSleep: true), 82)

        // Aug 9's own sleep-only score wins without a dailyMetric; August 8 is never borrowed.
        XCTAssertEqual(TodayView.restScoreForWakeDay(
            todayValue: 79.25, lastDay: "2026-08-08", lastValue: 82,
            isTodaySelected: true, todayKey: "2026-08-09", hasFinalizedSleep: true), 79.25)
        XCTAssertEqual(TodayView.restRingState(restScore: 79.25, sleepSession: aug9,
                                               hasRecovery: false),
                       .scored(79.25))
        let points = [MetricPoint(day: "2026-08-08", key: "sleep_performance", value: 82),
                      MetricPoint(day: "2026-08-09", key: "sleep_performance", value: 79.25)]
        XCTAssertEqual(SleepView.performanceValue(forWakeDay: "2026-08-09", in: points), 79.25)

        // Sleep page navigation is session-driven: newest wake-day first despite no Aug 9 daily row.
        let pageDays = SleepView.wakeDayGroups(rows, timeZone: budapest)
        XCTAssertEqual(pageDays.count, 2)
        XCTAssertEqual(pageDays[0], [aug9])
        XCTAssertEqual(pageDays[1], [aug8])

        // Activities/Today choose one canonical main session, not one row per overlapping fragment.
        XCTAssertEqual(Repository.sleepSessions(rows, forWakeDay: "2026-08-09",
                                                timeZone: budapest).count, 1)
    }

    func testMorningCarryStillWorksWhenNoNewFinalizedSessionExists() {
        XCTAssertEqual(TodayView.restScoreForWakeDay(
            todayValue: nil, lastDay: "2026-08-08", lastValue: 82,
            isTodaySelected: true, todayKey: "2026-08-09", hasFinalizedSleep: false), 82)
    }

    func testBudapestWakeDayUsesWakeNotStartCalendarDay() {
        // 22:30 UTC is 00:30 on Aug 9 in Budapest; the night started on Aug 8 local time.
        let crossing = session("2026-08-08T19:30:00Z", "2026-08-08T22:30:00Z")
        XCTAssertEqual(Repository.sleepWakeDayKey(crossing, timeZone: budapest), "2026-08-09")
        XCTAssertEqual(Repository.sleepSessions([crossing], forWakeDay: "2026-08-08",
                                                timeZone: budapest), [])
        XCTAssertEqual(Repository.sleepSessions([crossing], forWakeDay: "2026-08-09",
                                                timeZone: budapest), [crossing])
    }

    @MainActor
    func testCanonicalRepositoryPrecedenceAndReadsDoNotCreateDailyMetric() async throws {
        let store = try await WhoopStore.inMemory()
        let imported = session("2026-08-07T21:00:00Z", "2026-08-08T05:30:00Z")
        let computedTwin = session("2026-08-07T21:15:00Z", "2026-08-08T05:20:00Z", edited: true)
        let recovered = session("2026-08-09T01:27:14Z", "2026-08-09T09:07:34Z")
        _ = try await store.upsertSleepSessions([imported], deviceId: "my-whoop")
        _ = try await store.upsertSleepSessions([computedTwin, recovered], deviceId: "my-whoop-noop")

        let repo = Repository(deviceId: "my-whoop")
        repo.setStoreForTesting(store)
        let canonical = await repo.allSleepSessions(days: 10)

        XCTAssertEqual(Repository.sleepSession(forWakeDay: "2026-08-08", in: canonical,
                                               timeZone: budapest), imported,
                       "existing imported-over-computed precedence must not change")
        XCTAssertEqual(Repository.sleepSession(forWakeDay: "2026-08-09", in: canonical,
                                               timeZone: budapest), recovered)
        XCTAssertTrue(try await store.dailyMetrics(deviceId: "my-whoop-noop",
                                                   from: "2026-08-09", to: "2026-08-09").isEmpty)
    }

    @MainActor
    func testSleepPlanningIncludesSessionOnlyWakeDayAndUsesPreNightPlan() {
        let aug8Daily = DailyMetric(day: "2026-08-08", totalSleepMin: 450, efficiency: 0.9,
                                    deepMin: 90, remMin: 90, lightMin: 270, disturbances: 2,
                                    restingHr: 52, avgHrv: 60, recovery: 70, strain: 50,
                                    exerciseCount: 0)
        let aug8 = session("2026-08-07T21:00:00Z", "2026-08-08T05:30:00Z")
        let aug9 = session("2026-08-09T01:27:14Z", "2026-08-09T09:07:34Z")
        let inputs = SleepHistoryInputBuilder.build(
            days: [aug8Daily], sessions: [aug8, aug9], habitualMidsleepSec: nil,
            importedSleep: [:], timeZone: budapest)
        XCTAssertEqual(inputs.map(\.day), ["2026-08-08", "2026-08-09"])
        let result = SleepPlanningEngine.evaluate(inputs)
        let aug9Point = result.history.first(where: { $0.day == "2026-08-09" })
        XCTAssertNotNil(aug9Point?.actualMainSleepMinutes)
        XCTAssertEqual(aug9Point?.planBeforeNight.recentDebtMinutes,
                       result.history.first?.recentDebtMinutes,
                       "the displayed recovered night must use its no-look-ahead pre-night plan")
        XCTAssertGreaterThanOrEqual(result.tonight.recentDebtMinutes,
                                    aug9Point?.planBeforeNight.recentDebtMinutes ?? 0)
    }
}
