import XCTest
@testable import StrandAnalytics

final class SleepNeedEngineTests: XCTestCase {
    private func calculate(sleeps: [Double] = [], efficiencies: [Double] = [], debt: Double = 0,
                           strain: Double? = nil, naps: Double = 0) -> SleepNeedBreakdown {
        SleepNeedEngine.calculate(priorMainSleepMinutes: sleeps, priorEfficiencies: efficiencies,
                                  carriedDebtMinutes: debt, strain: strain,
                                  qualifyingNapSleepMinutes: naps)
    }

    func testFallbackAndConfidenceThresholds() {
        XCTAssertEqual(calculate().baselineMinutes, 450)
        XCTAssertEqual(calculate().confidence, .fallback)
        XCTAssertEqual(calculate(sleeps: Array(repeating: 480, count: 6)).confidence, .fallback)
        XCTAssertEqual(calculate(sleeps: Array(repeating: 480, count: 7)).confidence, .limited)
        XCTAssertEqual(calculate(sleeps: Array(repeating: 480, count: 20)).confidence, .limited)
        XCTAssertEqual(calculate(sleeps: Array(repeating: 480, count: 21)).confidence, .established)
    }

    func testPercentileBaselineAndClamps() {
        XCTAssertEqual(calculate(sleeps: [420, 430, 440, 450, 480, 500, 520]).baselineMinutes, 484)
        XCTAssertEqual(calculate(sleeps: Array(repeating: 360, count: 28)).baselineMinutes, 450)
        XCTAssertEqual(calculate(sleeps: Array(repeating: 600, count: 28)).baselineMinutes, 540)
    }

    func testDebtAdjustmentIsBounded() {
        XCTAssertEqual(calculate(debt: 100).debtAdjustmentMinutes, 50)
        XCTAssertEqual(calculate(debt: 1_000).debtAdjustmentMinutes, 120)
    }

    func testStrainMapping() {
        XCTAssertEqual(calculate(strain: nil).strainAdjustmentMinutes, 0)
        XCTAssertEqual(calculate(strain: 50).strainAdjustmentMinutes, 0)
        XCTAssertEqual(calculate(strain: 75).strainAdjustmentMinutes, 15)
        XCTAssertEqual(calculate(strain: 100).strainAdjustmentMinutes, 30)
        XCTAssertEqual(calculate(strain: 200).strainAdjustmentMinutes, 30)
    }

    func testNapCreditAndCapWithoutDoubleCounting() {
        XCTAssertEqual(calculate(naps: 60).napCreditMinutes, 48)
        XCTAssertEqual(calculate(naps: 300).napCreditMinutes, 120)
        let withNap = SleepNeedEngine.history([
            .init(day: "1", mainSleepMinutes: 450, napSleepMinutes: 60)
        ])[0]
        XCTAssertEqual(withNap.breakdown.totalSleepNeedMinutes, 402)
        XCTAssertEqual(withNap.nightlyDeficitMinutes, 0) // main sleep is not increased by the nap again
    }

    func testEfficiencyAndRecommendedTimeInBed() {
        XCTAssertNil(calculate(efficiencies: Array(repeating: 0.9, count: 6)).expectedEfficiency)
        let result = calculate(efficiencies: [0.70, 0.8, 0.9, 0.9, 0.95, 0.99, 90])
        XCTAssertEqual(result.expectedEfficiency, 0.9)
        XCTAssertEqual(result.recommendedTimeInBedMinutes, 500)
        XCTAssertEqual(calculate(efficiencies: Array(repeating: 0.5, count: 7)).expectedEfficiency, 0.75)
        XCTAssertEqual(calculate(efficiencies: Array(repeating: 1.0, count: 7)).expectedEfficiency, 0.98)
    }

    func testDebtAccumulatesBeyondRecommendationCapWithoutFreezing() {
        let points = SleepNeedEngine.history((1...5).map {
            .init(day: "\($0)", mainSleepMinutes: 390)
        })
        XCTAssertEqual(points.map(\.carriedDebtMinutes), [60, 120, 180, 240, 300])
        XCTAssertEqual(points[4].breakdown.debtAdjustmentMinutes, 120)
        XCTAssertEqual(points[4].nightlyDeficitMinutes, 60)
    }

    func testSurplusRepaysDebtAgainstRequirementExcludingDebt() {
        let points = SleepNeedEngine.history([
            .init(day: "1", mainSleepMinutes: 390),
            .init(day: "2", mainSleepMinutes: 450),
            .init(day: "3", mainSleepMinutes: 490),
            .init(day: "4", mainSleepMinutes: 530),
        ])
        XCTAssertEqual(points[0].carriedDebtMinutes, 60)
        XCTAssertEqual(points[1].carriedDebtMinutes, 60) // exact baseline is stable
        XCTAssertEqual(points[2].repaymentMinutes, 30)
        XCTAssertEqual(points[2].carriedDebtMinutes, 30)
        XCTAssertEqual(points[3].repaymentMinutes, 60)
        XCTAssertEqual(points[3].carriedDebtMinutes, 0)
        XCTAssertLessThan(points[3].breakdown.totalSleepNeedMinutes,
                          points[2].breakdown.totalSleepNeedMinutes)
    }

    func testSeveralGoodNightsReduceRecommendation() {
        var inputs = (1...21).map { SleepNeedNightInput(day: "baseline-\($0)", mainSleepMinutes: 450) }
        inputs += (1...4).map { SleepNeedNightInput(day: "bad-\($0)", mainSleepMinutes: 390) }
        inputs += (1...4).map { SleepNeedNightInput(day: "good-\($0)", mainSleepMinutes: 540) }
        let points = SleepNeedEngine.history(inputs)
        XCTAssertEqual(points[24].carriedDebtMinutes, 240)
        XCTAssertEqual(points[25].breakdown.debtAdjustmentMinutes, 120)
        XCTAssertEqual(points[28].carriedDebtMinutes, 0)
        XCTAssertLessThan(points[28].breakdown.totalSleepNeedMinutes,
                          points[25].breakdown.totalSleepNeedMinutes)
    }

    func testRescoringIsDeterministicAndIdempotent() {
        let inputs: [SleepNeedNightInput] = [
            .init(day: "2026-07-29", mainSleepMinutes: 390, strain: 75, efficiency: 0.94),
            .init(day: "2026-07-30", mainSleepMinutes: 510, napSleepMinutes: 30,
                  strain: 20, efficiency: 0.96),
        ]
        XCTAssertEqual(SleepNeedEngine.history(inputs), SleepNeedEngine.history(inputs))
    }

    func testHistoricalCalculationHasNoLookAhead() {
        let prefix: [SleepNeedNightInput] = (1...7).map { .init(day: "\($0)", mainSleepMinutes: 480) }
        let before = SleepNeedEngine.history(prefix)
        let after = SleepNeedEngine.history(prefix + [.init(day: "8", mainSleepMinutes: 540)])
        XCTAssertEqual(before, Array(after.prefix(7)))
        XCTAssertEqual(after[0].breakdown.confidence, .fallback)
        XCTAssertEqual(after[7].breakdown.confidence, .limited)
    }

    func testMissingPointVersusRealZeroAndGaps() {
        let points = SleepNeedEngine.history([
            .init(day: "1", mainSleepMinutes: nil),
            .init(day: "2", mainSleepMinutes: 450),
            .init(day: "3", mainSleepMinutes: nil),
        ])
        XCTAssertNil(points[0].carriedDebtMinutes)
        XCTAssertEqual(points[1].carriedDebtMinutes, 0)
        XCTAssertNil(points[2].carriedDebtMinutes)
    }

    func testMissingNightDoesNotDuplicateDebt() {
        let points = SleepNeedEngine.history([
            .init(day: "1", mainSleepMinutes: 390),
            .init(day: "2", mainSleepMinutes: nil),
            .init(day: "3", mainSleepMinutes: 450),
        ])
        XCTAssertEqual(points[0].carriedDebtMinutes, 60)
        XCTAssertNil(points[1].carriedDebtMinutes)
        XCTAssertEqual(points[2].carriedDebtMinutes, 60)
    }

    func testInputOrderingDefinesSleepDayBoundaryWithoutCalendarRebucketing() {
        let points = SleepNeedEngine.history([
            .init(day: "2026-03-29", mainSleepMinutes: 390),
            .init(day: "2026-03-30", mainSleepMinutes: 450),
        ])
        XCTAssertEqual(points.map(\.day), ["2026-03-29", "2026-03-30"])
        XCTAssertEqual(points.map(\.carriedDebtMinutes), [60, 60])
    }

    func testImportedWhoopReferencesRemainUntouched() {
        let point = SleepNeedEngine.history([
            .init(day: "1", mainSleepMinutes: 400, importedWhoopNeedMinutes: 510,
                  importedWhoopDebtMinutes: 87)
        ])[0]
        XCTAssertEqual(point.importedWhoopNeedMinutes, 510)
        XCTAssertEqual(point.importedWhoopDebtMinutes, 87)
        XCTAssertEqual(point.breakdown.totalSleepNeedMinutes, 450)
        XCTAssertEqual(point.carriedDebtMinutes, 50)
    }
}
