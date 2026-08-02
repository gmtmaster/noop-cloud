import XCTest
@testable import StrandAnalytics

final class NoopAgeEngineTests: XCTestCase {
    private func week(_ index: Int, age: Double? = 40, rhr: Double = 60,
                      hrv: Double = 55, debt: Double? = 30, workouts: Int = 3) -> NoopAgeWeekInput {
        NoopAgeWeekInput(weekEndDay: String(format: "2026-01-%02d", 3 + index * 7),
            chronologicalAge: age, sex: "male", restingHR: Array(repeating: rhr, count: 7),
            strain: [35, 50, 60, 0, 45, 0, 0], hrv: Array(repeating: hrv, count: 7),
            sleepMinutes: [470, 480, 475, 485, 470, 480, 475], recentSleepDebtMinutes: debt,
            recovery: [65, 70, 68, 72, 69, 66, 71], workoutCount: workouts)
    }

    func testHistoricalResultDoesNotChangeWhenFutureWeeksAreAdded() {
        let first = NoopAgeEngine.evaluate((0..<4).map { week($0) }).first
        let extended = NoopAgeEngine.evaluate((0..<7).map { week($0, rhr: $0 > 3 ? 85 : 60) }).first
        XCTAssertEqual(first, extended)
    }

    func testSelectedWeekUsesOnlyPrefixData() {
        let base = NoopAgeEngine.evaluate((0..<5).map { week($0) })
        let changedFuture = NoopAgeEngine.evaluate((0..<6).map { week($0, rhr: $0 == 5 ? 95 : 60) })
        XCTAssertEqual(base[4], changedFuture[4])
    }

    func testMissingMetricsLowerConfidenceWithoutCrash() {
        let sparse = NoopAgeWeekInput(weekEndDay: "2026-01-03", chronologicalAge: 40, sex: "male",
            restingHR: [60, 61, 59, 60], strain: [], hrv: [], sleepMinutes: [],
            recentSleepDebtMinutes: nil, recovery: [], workoutCount: 0)
        let result = NoopAgeEngine.evaluate([sparse])[0]
        XCTAssertNotNil(result.noopAge)
        XCTAssertEqual(result.confidence, .developing)
    }

    func testMissingAgeOrRHRIsInsufficient() {
        XCTAssertNil(NoopAgeEngine.evaluate([week(0, age: nil)])[0].noopAge)
        let short = NoopAgeWeekInput(weekEndDay: "2026-01-03", chronologicalAge: 40, sex: "male",
            restingHR: [60, 61, 59], strain: [], hrv: [], sleepMinutes: [],
            recentSleepDebtMinutes: nil, recovery: [], workoutCount: 0)
        XCTAssertEqual(NoopAgeEngine.evaluate([short])[0].confidence, .insufficient)
    }

    func testAgeAdjustmentIsBounded() {
        let result = NoopAgeEngine.evaluate([week(0, rhr: 120, hrv: 5, debt: 10_000, workouts: 0)])[0]
        XCTAssertGreaterThanOrEqual(result.noopAge!, 30)
        XCTAssertLessThanOrEqual(result.noopAge!, 50)
    }

    func testSmoothingPreventsFullWeeklyJump() {
        let results = NoopAgeEngine.evaluate([week(0, rhr: 50), week(1, rhr: 50), week(2, rhr: 100)])
        XCTAssertLessThan(abs(results[2].noopAge! - results[1].noopAge!),
                          abs(results[2].rawAge! - results[1].rawAge!))
    }

    func testPaceRequiresFourWeeksAndStaysBounded() {
        let results = NoopAgeEngine.evaluate((0..<8).map { week($0, rhr: 45 + Double($0) * 7) })
        XCTAssertNil(results[2].paceOfAging)
        XCTAssertNotNil(results[3].paceOfAging)
        for value in results.compactMap(\.paceOfAging) {
            XCTAssertTrue(NoopAgeEngine.Configuration.minimumPace...NoopAgeEngine.Configuration.maximumPace ~= value)
        }
    }

    func testContributorDirectionsMatchAdjustments() {
        let result = NoopAgeEngine.evaluate([week(0, rhr: 85, debt: 240, workouts: 0)])[0]
        XCTAssertTrue(result.contributors.allSatisfy {
            ($0.adjustmentYears <= 0 && $0.impact == .helping) ||
            ($0.adjustmentYears > 0 && $0.impact == .holdingBack)
        })
        XCTAssertEqual(result.contributors.first { $0.key == "sleep_debt" }?.impact, .holdingBack)
    }
}
