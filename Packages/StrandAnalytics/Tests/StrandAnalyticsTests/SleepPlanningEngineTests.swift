import XCTest
@testable import StrandAnalytics

final class SleepPlanningEngineTests: XCTestCase {
    private func inputs(_ sleeps: [Double], strain: Double? = nil) -> [SleepPlanningNightInput] {
        sleeps.enumerated().map { .init(day: "d\($0.offset)", mainSleepMinutes: $0.element, strain: strain) }
    }

    func testRepeatedShortSleepGrowsDebt() {
        let result = SleepPlanningEngine.evaluate(inputs([390, 390, 390]))
        let debts = result.history.compactMap(\.recentDebtMinutes)
        XCTAssertEqual(debts.count, 3)
        XCTAssertGreaterThan(debts[2], debts[1])
        XCTAssertGreaterThan(debts[1], debts[0])
    }

    func testDebtIsBoundedAndOldHistoryCannotChangeCurrentResult() {
        let old = inputs(Array(repeating: 600, count: 40))
        let recent = inputs(Array(repeating: 480, count: SleepPlanningEngine.Configuration.maximumInputHistoryNights))
        let withOld = SleepPlanningEngine.evaluate(old + recent).tonight
        let withoutOld = SleepPlanningEngine.evaluate(recent).tonight
        XCTAssertEqual(withOld, withoutOld)
        XCTAssertEqual(SleepPlanningEngine.Configuration.debtWindowNights, 14)
        XCTAssertEqual(SleepPlanningEngine.evaluate(old + recent).recentContributions.count, 14)
    }

    func testOldDeficitFadesAndLeavesWindow() {
        let start = SleepPlanningEngine.evaluate(inputs([390])).tonight.recentDebtMinutes
        let faded = SleepPlanningEngine.evaluate(inputs([390] + Array(repeating: 450, count: 5))).tonight.recentDebtMinutes
        let gone = SleepPlanningEngine.evaluate(inputs([390] + Array(repeating: 450, count: 14))).tonight.recentDebtMinutes
        XCTAssertLessThan(faded, start)
        XCTAssertEqual(gone, 0)
    }

    func testRecentDeficitContributesMoreThanOlderDeficit() {
        let old = SleepPlanningEngine.evaluate(inputs([390] + Array(repeating: 450, count: 5))).tonight.recentDebtMinutes
        let recent = SleepPlanningEngine.evaluate(inputs(Array(repeating: 450, count: 5) + [390])).tonight.recentDebtMinutes
        XCTAssertGreaterThan(recent, old)
    }

    func testSurplusReducesDebtAndDebtNeverGoesNegative() {
        let result = SleepPlanningEngine.evaluate(inputs([390, 510, 600]))
        XCTAssertLessThan(result.history[1].recentDebtMinutes!, result.history[0].recentDebtMinutes!)
        XCTAssertGreaterThanOrEqual(result.tonight.recentDebtMinutes, 0)
    }

    func testMissingNightDoesNotCreateDebt() {
        let result = SleepPlanningEngine.evaluate([
            .init(day: "1", mainSleepMinutes: 390), .init(day: "2", mainSleepMinutes: nil)
        ])
        XCTAssertNil(result.history[1].recentDebtMinutes)
        XCTAssertEqual(result.tonight.recentDebtMinutes, result.history[0].recentDebtMinutes!)
    }

    func testNapReducesNeedWithoutChangingBaseline() {
        let none = SleepPlanningEngine.evaluate([], tonightNapSleepMinutes: 0).tonight
        let nap = SleepPlanningEngine.evaluate([], tonightNapSleepMinutes: 60).tonight
        XCTAssertEqual(nap.baselineMinutes, none.baselineMinutes)
        XCTAssertEqual(nap.napCreditMinutes, 48)
        XCTAssertEqual(nap.sleepNeedMinutes, none.sleepNeedMinutes - 48)
    }

    func testSmoothStrainCurveAndCap() {
        XCTAssertEqual(SleepPlanningEngine.strainAdjustment(for: 0), 0)
        XCTAssertLessThan(SleepPlanningEngine.strainAdjustment(for: 20), 2)
        XCTAssertGreaterThan(SleepPlanningEngine.strainAdjustment(for: 70), 10)
        XCTAssertEqual(SleepPlanningEngine.strainAdjustment(for: 100), 30)
        XCTAssertEqual(SleepPlanningEngine.strainAdjustment(for: 500), 30)
    }

    func testHistoricalRequirementExcludesDebtRecovery() {
        let result = SleepPlanningEngine.evaluate(inputs([390, 450]))
        XCTAssertGreaterThan(result.history[1].planBeforeNight.debtRecoveryMinutes, 0)
        XCTAssertEqual(result.history[1].deficitMinutes, 0)
        XCTAssertEqual(result.history[1].baseRequirementMinutes, 450)
    }

    func testDebtRecoveryIsSeparateAndCapped() {
        let result = SleepPlanningEngine.evaluate(inputs(Array(repeating: 300, count: 14)))
        XCTAssertGreaterThan(result.tonight.recentDebtMinutes, result.tonight.debtRecoveryMinutes)
        XCTAssertEqual(result.tonight.debtRecoveryMinutes, 60)
    }

    func testHistoricalProjectionHasNoLookAhead() {
        let prefix = inputs(Array(repeating: 450, count: 8))
        let before = SleepPlanningEngine.evaluate(prefix).history
        let after = SleepPlanningEngine.evaluate(prefix + [.init(day: "future", mainSleepMinutes: 300)]).history
        XCTAssertEqual(before, Array(after.prefix(before.count)))
    }

    func testImportedValuesRemainReferencesOnly() {
        let point = SleepPlanningEngine.evaluate([
            .init(day: "1", mainSleepMinutes: 400, importedWhoopNeedMinutes: 600,
                  importedWhoopDebtMinutes: 999)
        ]).history[0]
        XCTAssertEqual(point.importedWhoopNeedMinutes, 600)
        XCTAssertEqual(point.importedWhoopDebtMinutes, 999)
        XCTAssertEqual(point.planBeforeNight.sleepNeedMinutes, 450)
        XCTAssertEqual(point.recentDebtMinutes, 50)
    }

    func testEfficiencyControlsTimeInBedWithFallbackAndPersonalHistory() {
        XCTAssertEqual(SleepPlanningEngine.evaluate([]).tonight.expectedEfficiency, 0.9)
        let history = (0..<7).map { SleepPlanningNightInput(day: "\($0)", mainSleepMinutes: 450, efficiency: 0.8) }
        let plan = SleepPlanningEngine.evaluate(history).tonight
        XCTAssertEqual(plan.expectedEfficiency, 0.8)
        XCTAssertEqual(plan.timeInBedMinutes, plan.sleepNeedMinutes / 0.8, accuracy: 0.1)
    }

    func testRecommendedBedtimeSubtractsTimeInBed() {
        let wake = Date(timeIntervalSince1970: 10_000)
        XCTAssertEqual(SleepPlanningEngine.recommendedBedtime(plannedWake: wake, timeInBedMinutes: 500),
                       wake.addingTimeInterval(-30_000))
    }
}
