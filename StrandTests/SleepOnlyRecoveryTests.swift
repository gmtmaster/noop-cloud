import XCTest
import Foundation
import WhoopProtocol
import WhoopStore
import StrandAnalytics
@testable import Strand

/// Regression coverage for the August 2026 missing-night repair. The recovery is intentionally exercised
/// against a real in-memory WhoopStore so the assertions cover detector input reads, insert-only persistence,
/// Repository exposure, and the absence of any dailyMetric mutation.
final class SleepOnlyRecoveryTests: XCTestCase {
    private let deviceId = "my-whoop"
    private let computedId = "my-whoop-noop"
    private let budapestOffset = 2 * 3_600

    private func utc(_ value: String) -> Date {
        ISO8601DateFormatter().date(from: value)!
    }

    private func daily(_ day: String, recovery: Double, strain: Double, calories: Double) -> DailyMetric {
        DailyMetric(day: day, totalSleepMin: 480, efficiency: 0.9, deepMin: 120,
                    remMin: 130, lightMin: 230, disturbances: 2, restingHr: 52,
                    avgHrv: 65, recovery: recovery, strain: strain, exerciseCount: 1,
                    spo2Pct: 96, skinTempDevC: 0.1, respRateBpm: 13, steps: 12_345,
                    activeKcalEst: calories)
    }

    private func seedFinalizableNight(_ store: WhoopStore) async throws {
        // 2026-08-09 01:00→02:30 Budapest: accepted still/low-HR sleep, followed by 30 minutes of
        // active/high-HR data. The post-wake tail clears recovery's finalization guard.
        let sleepStart = Int(utc("2026-08-08T23:00:00Z").timeIntervalSince1970)
        let sleepSeconds = 90 * 60
        let tailSeconds = 30 * 60
        let hr = (0..<(sleepSeconds + tailSeconds)).map { i in
            HRSample(ts: sleepStart + i, bpm: i < sleepSeconds ? 50 : 72)
        }
        let gravity = (0..<(sleepSeconds + tailSeconds)).map { i -> GravitySample in
            let x = i < sleepSeconds ? 0.0 : Double(i % 2) * 0.5
            return GravitySample(ts: sleepStart + i, x: x, y: 0, z: 1)
        }
        _ = try await store.insert(Streams(hr: hr, gravity: gravity), deviceId: deviceId)
    }

    @MainActor
    func testRecoveryAddsMissingAug9SleepWithoutChangingAug7OrAug8DailyRows() async throws {
        let store = try await WhoopStore.inMemory()
        try await store.upsertDevice(id: deviceId, mac: nil, name: "WHOOP")
        let aug7 = daily("2026-08-07", recovery: 78.053, strain: 19.63, calories: 2009.083)
        let aug8 = daily("2026-08-08", recovery: 10.7854, strain: 28.92, calories: 1846.456)
        _ = try await store.upsertDailyMetrics([aug7, aug8], deviceId: computedId)
        let existingAug8 = CachedSleepSession(
            startTs: Int(utc("2026-08-07T22:17:27Z").timeIntervalSince1970),
            endTs: Int(utc("2026-08-08T07:35:00Z").timeIntervalSince1970),
            efficiency: 0.914806, restingHr: 57, avgHrv: 42.8506,
            stagesJSON: "[\"aug8-existing\"]", userEdited: true)
        _ = try await store.upsertSleepSessions([existingAug8], deviceId: computedId)
        try await seedFinalizableNight(store)

        let before = try await store.dailyMetrics(deviceId: computedId,
                                                  from: "2026-08-07", to: "2026-08-08")
        let repo = Repository(deviceId: deviceId)
        repo.setStoreForTesting(store)
        let engine = IntelligenceEngine(repo: repo, profile: ProfileStore(), deviceId: deviceId)
        let now = utc("2026-08-09T04:00:00Z") // 06:00 Budapest

        let first = await engine.recoverMissingRecentSleep(maxWakeDays: 2, now: now,
                                                           tzOffsetSeconds: budapestOffset)
        XCTAssertEqual(first.inserted.count, 1)
        XCTAssertEqual(first.sleepPerformancePoints.count, 1)
        XCTAssertEqual(first.sleepPerformancePoints.first?.day, "2026-08-09")
        XCTAssertEqual(first.sleepPerformancePoints.first?.key, "sleep_performance")
        XCTAssertEqual(first.existingDays, 1, "the valid Aug 8 sleep must skip detection and persistence")
        let dailyAfterFirst = try await store.dailyMetrics(deviceId: computedId,
                                                           from: "2026-08-07", to: "2026-08-08")
        XCTAssertEqual(dailyAfterFirst, before,
                       "Aug 7/Aug 8 daily rows, including Recovery/Strain/calories, must be identical")

        let stored = try await store.sleepSessions(deviceId: computedId,
                                                   from: Int(utc("2026-08-07T00:00:00Z").timeIntervalSince1970),
                                                   to: Int(now.timeIntervalSince1970), limit: 100)
        XCTAssertEqual(stored.count, 2)
        XCTAssertEqual(stored.first, existingAug8, "the existing edited Aug 8 sleep must not be rewritten")
        XCTAssertTrue(repo.sleeps.contains(where: { $0.startTs == first.inserted[0].startTs }),
                      "Repository refresh must expose recovered sleep without an Aug 9 dailyMetric")
        let aug9Dailies = try await store.dailyMetrics(deviceId: computedId,
                                                       from: "2026-08-09", to: "2026-08-09")
        XCTAssertTrue(aug9Dailies.isEmpty,
                      "sleep-only recovery must not create a partial dailyMetric")
        let aug9Rest = try await store.metricSeries(deviceId: computedId, key: "sleep_performance",
                                                    from: "2026-08-09", to: "2026-08-09")
        XCTAssertEqual(aug9Rest, first.sleepPerformancePoints)
        let canonicalFromPersisted = try XCTUnwrap(AnalyticsEngine.Rest.composite(
            finalized: first.inserted, offsetSec: budapestOffset))
        XCTAssertEqual(try XCTUnwrap(aug9Rest.first?.value), canonicalFromPersisted,
                       accuracy: 0.000_001)

        let second = await engine.recoverMissingRecentSleep(maxWakeDays: 2, now: now,
                                                            tzOffsetSeconds: budapestOffset)
        XCTAssertTrue(second.inserted.isEmpty, "a second recovery pass must be a strict no-op")
        XCTAssertTrue(second.sleepPerformancePoints.isEmpty,
                      "a second recovery pass must not rewrite the existing Rest point")
        let sessionsAfterSecond = try await store.sleepSessions(deviceId: computedId,
                                                                from: 0, to: Int(now.timeIntervalSince1970),
                                                                limit: 100)
        let dailyAfterSecond = try await store.dailyMetrics(deviceId: computedId,
                                                            from: "2026-08-07", to: "2026-08-08")
        XCTAssertEqual(sessionsAfterSecond.count, 2)
        XCTAssertEqual(dailyAfterSecond, before)
        XCTAssertEqual(try await store.metricSeries(deviceId: computedId, key: "sleep_performance",
                                                     from: "2026-08-09", to: "2026-08-09").count, 1)
    }

    @MainActor
    func testInsufficientOvernightStreamMutatesNothing() async throws {
        let store = try await WhoopStore.inMemory()
        try await store.upsertDevice(id: deviceId, mac: nil, name: "WHOOP")
        let aug8 = daily("2026-08-08", recovery: 10.7854, strain: 28.92, calories: 1846.456)
        _ = try await store.upsertDailyMetrics([aug8], deviceId: computedId)
        let start = Int(utc("2026-08-08T23:00:00Z").timeIntervalSince1970)
        let short = 30 * 60
        _ = try await store.insert(Streams(
            hr: (0..<short).map { HRSample(ts: start + $0, bpm: 50) },
            gravity: (0..<short).map { GravitySample(ts: start + $0, x: 0, y: 0, z: 1) }),
            deviceId: deviceId)

        let repo = Repository(deviceId: deviceId)
        repo.setStoreForTesting(store)
        let engine = IntelligenceEngine(repo: repo, profile: ProfileStore(), deviceId: deviceId)
        let result = await engine.recoverMissingRecentSleep(
            maxWakeDays: 1, now: utc("2026-08-09T04:00:00Z"), tzOffsetSeconds: budapestOffset)

        XCTAssertTrue(result.inserted.isEmpty)
        let sleeps = try await store.sleepSessions(deviceId: computedId, from: 0, to: Int.max, limit: 100)
        let dailies = try await store.dailyMetrics(deviceId: computedId,
                                                   from: "2026-08-08", to: "2026-08-08")
        XCTAssertTrue(sleeps.isEmpty)
        XCTAssertEqual(dailies, [aug8])
    }

    @MainActor
    func testPreviouslyRecoveredSessionReceivesMissingScoreWithoutRedetection() async throws {
        let store = try await WhoopStore.inMemory()
        try await store.upsertDevice(id: deviceId, mac: nil, name: "WHOOP")
        let stages = #"{"awake":28.833333333333332,"light":204.0,"deep":98.0,"rem":129.5}"#
        let recovered = CachedSleepSession(startTs: 1_786_238_834, endTs: 1_786_266_454,
                                           efficiency: 0.9373642288196958,
                                           restingHr: 52, avgHrv: 64, stagesJSON: stages)
        _ = try await store.insertRecoveredSleepSession(recovered, deviceId: computedId)
        let repo = Repository(deviceId: deviceId)
        repo.setStoreForTesting(store)
        let engine = IntelligenceEngine(repo: repo, profile: ProfileStore(), deviceId: deviceId)

        let first = await engine.recoverMissingRecentSleep(
            maxWakeDays: 1, now: utc("2026-08-09T10:00:00Z"),
            tzOffsetSeconds: budapestOffset)
        XCTAssertTrue(first.inserted.isEmpty)
        XCTAssertEqual(first.sleepPerformancePoints,
                       [MetricPoint(day: "2026-08-09", key: "sleep_performance", value: 88.7)])
        XCTAssertTrue(try await store.dailyMetrics(deviceId: computedId,
                                                   from: "2026-08-09", to: "2026-08-09").isEmpty)

        let second = await engine.recoverMissingRecentSleep(
            maxWakeDays: 1, now: utc("2026-08-09T10:00:00Z"),
            tzOffsetSeconds: budapestOffset)
        XCTAssertTrue(second.sleepPerformancePoints.isEmpty)
        XCTAssertEqual(try await store.metricSeries(deviceId: computedId, key: "sleep_performance",
                                                     from: "2026-08-09", to: "2026-08-09").count, 1)
    }
}
