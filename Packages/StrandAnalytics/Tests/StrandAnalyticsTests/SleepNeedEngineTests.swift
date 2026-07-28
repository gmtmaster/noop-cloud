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

    func testDeficitDecayRepaymentAndMaximumDebt() {
        let deficit = SleepNeedEngine.history([
            .init(day: "1", mainSleepMinutes: 390), // +60
            .init(day: "2", mainSleepMinutes: 450), // 60*.9 + 30 adjustment deficit
            .init(day: "3", mainSleepMinutes: 600), // partial surplus repayment
        ])
        XCTAssertEqual(deficit[0].carriedDebtMinutes, 60)
        XCTAssertEqual(deficit[1].carriedDebtMinutes, 84)
        XCTAssertEqual(deficit[2].repaymentMinutes, 81)
        XCTAssertEqual(deficit[2].carriedDebtMinutes, 0)

        let capped = SleepNeedEngine.history((1...10).map {
            .init(day: "\($0)", mainSleepMinutes: 60)
        })
        XCTAssertEqual(capped.last?.carriedDebtMinutes, 240)
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
