import XCTest
@testable import StrandAnalytics

final class HealthspanPresentationTests: XCTestCase {
    private func date(_ value: String, timeZone: TimeZone) -> Date {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = timeZone; f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return f.date(from: value)!
    }

    func testSundayLocalMidnightIncludesSaturdayEndedWeekAcrossOffsets() {
        for seconds in [-8 * 3600, 0, 2 * 3600, 12 * 3600] {
            let zone = TimeZone(secondsFromGMT: seconds)!, now = date("2026-08-02 00:00:00", timeZone: zone)
            var calendar = Calendar(identifier: .gregorian); calendar.timeZone = zone
            XCTAssertEqual(HealthspanWeekCutoff.latestCompletedWeekEnd(now: now, calendar: calendar), "2026-08-01")
        }
    }

    func testSaturdayDoesNotPrematurelyCloseCurrentWeek() {
        let zone = TimeZone(secondsFromGMT: 2 * 3600)!, now = date("2026-08-01 23:59:59", timeZone: zone)
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = zone
        XCTAssertEqual(HealthspanWeekCutoff.latestCompletedWeekEnd(now: now, calendar: calendar), "2026-07-25")
    }

    func testDirectionThresholdsAreIndependentOfConfidence() {
        XCTAssertEqual(HealthspanDirection.classify(delta: -0.4), .improving)
        XCTAssertEqual(HealthspanDirection.classify(delta: 0.4), .worsening)
        XCTAssertEqual(HealthspanDirection.classify(delta: -0.24), .neutral)
        XCTAssertEqual(HealthspanDirection.classify(delta: 0.24), .neutral)
    }

    func testContributorAvailabilityDistinguishesBaselineCoverageAndValid() {
        let coverage = NoopAgeCoverage(calendarDays: 45, validWearDays: 40, sleepNights: 38,
            rhrDays: 40, activityDays: 40, validWeeks: 7, representedDomains: 3,
            missingProportion: 0.1, unavailableContributorKeys: [])
        let contributor = NoopAgeContributor(key: "steps", label: "Steps", domain: .activity,
                                             adjustmentYears: -0.2, recentAdjustmentYears: -0.1)
        func result(pace: Double?, contributors: [NoopAgeContributor], domains: Int = 3) -> NoopAgeWeekResult {
            let c = NoopAgeCoverage(calendarDays: coverage.calendarDays, validWearDays: coverage.validWearDays,
                sleepNights: coverage.sleepNights, rhrDays: coverage.rhrDays, activityDays: coverage.activityDays,
                validWeeks: coverage.validWeeks, representedDomains: domains,
                missingProportion: coverage.missingProportion, unavailableContributorKeys: [])
            return NoopAgeWeekResult(weekEndDay: "2026-08-01", rawAge: 39, noopAge: 39,
                paceOfAging: pace, confidence: .developing, contributors: contributors,
                ageContributors: [], coverage: c, modelVersion: "test")
        }
        XCTAssertEqual(HealthspanContributorAvailability.resolve(result(pace: nil, contributors: [contributor])),
                       .buildingPaceBaseline)
        XCTAssertEqual(HealthspanContributorAvailability.resolve(result(pace: 1, contributors: [], domains: 1)),
                       .insufficientComparableData)
        XCTAssertEqual(HealthspanContributorAvailability.resolve(result(pace: 1, contributors: [contributor])), .valid)
    }

    func testSelectionDefaultsToNewestCompletedSnapshot() {
        XCTAssertEqual(HealthspanSelection.newestIndex(count: 5), 4)
        XCTAssertEqual(HealthspanSelection.newestIndex(count: 0), 0)
    }

    func testPaceValueFormattingAndCalibrationCopy() {
        XCTAssertEqual(HealthspanPacePresentation.value(nil), "—")
        XCTAssertEqual(HealthspanPacePresentation.value(0.94), "0.9x")
        let eligibility = NoopAgeEngine.PaceEligibility(recentWearDays: 18, olderWearDays: 12,
            validWeeks: 5, recentDomains: 3, olderDomains: 2)
        XCTAssertEqual(HealthspanPacePresentation.calibrationDetail(eligibility),
            "Recent window 18 of 21 · older baseline 12 of 28 · 5 of 8 weeks")
    }
}
