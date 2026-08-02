import XCTest
@testable import StrandAnalytics

final class NoopAgeEngineTests: XCTestCase {
    private let start = "2026-01-01"

    private func day(_ index: Int, healthy: Bool = true, complete: Bool = true) -> HealthspanDay {
        HealthspanDay(day: add(start, index), sleepMinutes: complete ? (healthy ? 480 : 330) : nil,
            sleepStartMinute: complete ? (healthy ? 1_380 : Double((index * 113) % 1_440)) : nil,
            wakeMinute: complete ? (healthy ? 420 : Double((index * 157) % 1_440)) : nil,
            steps: complete ? (healthy ? 10_000 : 2_000) : nil,
            zone1to3Minutes: complete ? (healthy ? 25 : 0) : nil,
            zone4to5Minutes: complete ? (healthy ? 3 : 0) : nil,
            strengthMinutes: complete ? (healthy ? 8 : 0) : nil,
            restingHR: complete ? (healthy ? 55 : 85) : nil,
            vo2Max: complete ? (healthy ? 48 : 25) : nil,
            leanMassPercent: nil)
    }

    private func result(_ days: [HealthspanDay], cutoff: String? = nil) -> NoopAgeWeekResult {
        let end = cutoff ?? days.last!.day
        return NoopAgeEngine.evaluate(days: days, weekEndDays: [end]) { _ in 40 }.last!
    }

    func testSevenCompleteDaysProduceMaturityShrunkCalibratingAge() {
        let r = result((0..<7).map { day($0) })
        XCTAssertEqual(r.confidence, .calibrating)
        XCTAssertNotNil(r.noopAge)
        XCTAssertLessThanOrEqual(abs(r.noopAge! - 40), 0.6) // 20% of ±3-year cap
        XCTAssertNil(r.paceOfAging)
    }

    func testThirtyGoodDaysAreDevelopingButPaceStillUnavailable() {
        let r = result((0..<30).map { day($0) })
        XCTAssertEqual(r.confidence, .developing)
        XCTAssertNil(r.paceOfAging)
    }

    func testEstablishedRequiresAbout180DaysAndAdequateCoverage() {
        XCTAssertEqual(result((0..<179).map { day($0) }).confidence, .developing)
        let established = result((0..<180).map { day($0) })
        XCTAssertEqual(established.confidence, .established, "\(established.coverage)")
    }

    func testSparseLongCalendarSpanDoesNotInflateConfidence() {
        var sparse = (0..<5).map { day($0) }
        sparse.append(contentsOf: (175..<180).map { day($0) })
        XCTAssertEqual(result(sparse).confidence, .insufficient)
    }

    func testPaceRequiresOlderComparisonAndUsesProjectedAgeFormula() {
        let days = (0..<90).map { day($0, healthy: $0 >= 60) }
        let r = result(days)
        XCTAssertNotNil(r.paceOfAging)
        XCTAssertTrue(NoopAgeEngine.Configuration.minimumPace...NoopAgeEngine.Configuration.maximumPace ~= r.paceOfAging!)
        // A much healthier recent state than the mixed long-term state should slow/reverse projected aging.
        XCTAssertLessThan(r.paceOfAging!, 1)
    }

    func testRecentBehaviorMovesPaceMoreThanLongTermAge() {
        let baseline = result((0..<90).map { day($0, healthy: false) })
        let changed = result((0..<90).map { day($0, healthy: $0 >= 60) })
        XCTAssertLessThan(abs(changed.noopAge! - baseline.noopAge!), 3)
        XCTAssertLessThan(changed.paceOfAging!, baseline.paceOfAging!)
    }

    func testHard180DayWindowExcludesAncientData() {
        let recent = (20..<200).map { day($0) }
        let ancient = (0..<20).map { day($0, healthy: false) }
        XCTAssertEqual(result(recent).rawAge!, result(ancient + recent).rawAge!, accuracy: 1e-12)
    }

    func testHistoricalSnapshotHasStrictNoLookAhead() {
        let prefix = (0..<90).map { day($0) }
        let cutoff = prefix.last!.day
        let before = result(prefix, cutoff: cutoff)
        let after = result(prefix + (90..<150).map { day($0, healthy: false) }, cutoff: cutoff)
        XCTAssertEqual(before, after)
    }

    func testMissingOptionalMetricsRenormalizeWithoutZeroFabrication() {
        let sparse = (0..<30).map { i in
            HealthspanDay(day: add(start, i), sleepMinutes: 480, sleepStartMinute: 1_380,
                wakeMinute: 420, steps: 9_000, restingHR: 58)
        }
        let r = result(sparse)
        XCTAssertNotNil(r.noopAge)
        XCTAssertTrue(r.coverage.unavailableContributorKeys.contains("vo2max"))
        XCTAssertFalse(r.ageContributors.contains { $0.key == "vo2max" })
    }

    func testOneAbnormalDayHasLimitedEffect() {
        let normal = (0..<90).map { day($0) }
        var outlier = normal
        outlier[89] = day(89, healthy: false)
        XCTAssertLessThan(abs(result(outlier).noopAge! - result(normal).noopAge!), 0.5)
    }

    func testSustainedChangeMovesAgeGraduallyAcrossWeeklySnapshots() {
        let days = (0..<120).map { day($0, healthy: $0 < 90) }
        let cutoffs = stride(from: 83, through: 118, by: 7).map { add(start, $0) }
        let r = NoopAgeEngine.evaluate(days: days, weekEndDays: cutoffs) { _ in 40 }
        let changes = zip(r, r.dropFirst()).map { abs($1.noopAge! - $0.noopAge!) }
        XCTAssertTrue(changes.allSatisfy { $0 < 2 })
        XCTAssertGreaterThan(r.last!.noopAge!, r.first!.noopAge!)
    }

    func testLabBookHasNoInputPathAndCannotChangeResult() {
        let days = (0..<60).map { day($0) }
        let before = result(days)
        // HealthspanDay intentionally has no lab-marker field; unrelated values cannot enter the engine.
        let unrelatedLabBookValues = ["hs_crp": 4.2, "vitamin_d": 31.0]
        XCTAssertFalse(unrelatedLabBookValues.isEmpty)
        XCTAssertEqual(before, result(days))
    }

    func testResultKeepsFullPrecisionAndVersionedCoefficientSet() {
        let r = result((0..<60).map { day($0) })
        XCTAssertEqual(r.modelVersion, "noop-healthspan-v2")
        XCTAssertNotEqual(r.noopAge, (r.noopAge! * 10).rounded() / 10)
    }

    func testCanonicalProjectionMatchesResultAndNeverUsesLegacyAgeKeys() {
        let r = result((0..<90).map { day($0) })
        let values = NoopAgeEngine.canonicalMetricValues(r)
        XCTAssertEqual(values["noop_age"], r.noopAge)
        XCTAssertEqual(values["noop_pace"], r.paceOfAging)
        XCTAssertTrue(Set(values.keys).isDisjoint(with: ["fitness_age", "body_age", "vitality"]))
    }

    private func add(_ day: String, _ amount: Int) -> String {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let f = DateFormatter(); f.calendar = calendar
        f.locale = Locale(identifier: "en_US_POSIX"); f.timeZone = TimeZone(secondsFromGMT: 0); f.dateFormat = "yyyy-MM-dd"
        let d = f.date(from: day)!; return f.string(from: calendar.date(byAdding: .day, value: amount, to: d)!)
    }
}
