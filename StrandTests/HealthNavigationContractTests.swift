import XCTest
@testable import Strand

final class HealthNavigationContractTests: XCTestCase {
    func testHealthReplacesTrendsInPrimaryTabs() {
        XCTAssertEqual(HealthNavigationContract.primaryTabs,
                       ["Today", "Health", "Sleep", "Friends", "More"])
        XCTAssertEqual(HealthNavigationContract.healthTabIndex, 1)
        XCTAssertFalse(HealthNavigationContract.primaryTabs.contains("Trends"))
    }

    func testTrendsRemainsASecondaryDestination() {
        XCTAssertTrue(HealthNavigationContract.trendsRemainsSecondary)
        XCTAssertTrue(NavItem.allCases.contains(.trends))
    }

    func testReduceMotionAndInactiveSceneDisableOrbAnimation() {
        XCTAssertFalse(HealthspanAnimationPolicy.animates(reduceMotion: true, sceneIsActive: true))
        XCTAssertFalse(HealthspanAnimationPolicy.animates(reduceMotion: false, sceneIsActive: false))
        XCTAssertTrue(HealthspanAnimationPolicy.animates(reduceMotion: false, sceneIsActive: true))
    }

    func testOrbMotionIsDeterministicAndProgressesWithTime() {
        XCTAssertEqual(HealthspanOrbMotion.particle(index: 17, elapsed: 3),
                       HealthspanOrbMotion.particle(index: 17, elapsed: 3))
        XCTAssertNotEqual(HealthspanOrbMotion.particle(index: 17, elapsed: 3),
                          HealthspanOrbMotion.particle(index: 17, elapsed: 6))
        XCTAssertNotEqual(HealthspanOrbMotion.shellScale(at: 0), HealthspanOrbMotion.shellScale(at: 2))
    }

    func testContributorScaleSortsByMagnitudeAndBoundsOutliers() {
        XCTAssertTrue(HealthspanContributorScale.sortsBefore(lhsLabel: "Large", lhsAdjustment: 4,
                                                             rhsLabel: "Small", rhsAdjustment: -0.2))
        XCTAssertFalse(HealthspanContributorScale.sortsBefore(lhsLabel: "Small", lhsAdjustment: -0.2,
                                                              rhsLabel: "Large", rhsAdjustment: 4))
        XCTAssertEqual(HealthspanContributorScale.position(for: 20), 1)
        XCTAssertEqual(HealthspanContributorScale.position(for: -20), -1)
        XCTAssertLessThan(HealthspanContributorScale.position(for: -0.5), 0)
        XCTAssertGreaterThan(HealthspanContributorScale.position(for: 0.5), 0)
    }

    #if os(iOS)
    func testMoreKeepsSecondaryDestinationsWithoutPrimaryDuplicates() {
        XCTAssertEqual(MoreInformationArchitecture.featured, ["Lab Book", "Trends"])
        XCTAssertTrue(MoreInformationArchitecture.allVisible.contains("Devices"))
        XCTAssertTrue(MoreInformationArchitecture.allVisible.contains("Profile"))
        XCTAssertTrue(MoreInformationArchitecture.allVisible.contains("Test Centre"))
        for duplicate in MoreInformationArchitecture.topLevelDuplicates {
            XCTAssertFalse(MoreInformationArchitecture.allVisible.contains(duplicate))
        }
    }

    func testLabBookTrendRequiresTwoRealValues() {
        XCTAssertEqual(LabBookView.trendDescription(values: []), "Insufficient history")
        XCTAssertEqual(LabBookView.trendDescription(values: [4.2]), "Insufficient history")
        XCTAssertEqual(LabBookView.trendDescription(values: [4.2, 4.5]), "Trending up")
        XCTAssertEqual(LabBookView.trendDescription(values: [4.5, 4.2]), "Trending down")
    }

    func testTodayHeaderNeverLabelsFutureNavigationAsAvailable() {
        XCTAssertFalse(TodayView.canNavigateForward(offset: 0))
        XCTAssertTrue(TodayView.canNavigateForward(offset: 1))
        XCTAssertEqual(TodayView.compactDayLabel(offset: 0, date: Date()), "TODAY")
    }

    func testDeviceHeaderOmitsUnknownBatteryInsteadOfInventingZero() {
        let unknown = TodayDeviceHeaderPresentation.make(hasActiveDevice: true, connected: false,
                                                         batteryPct: nil)
        XCTAssertEqual(unknown.tone, .disconnected)
        XCTAssertNil(unknown.batteryText)

        let connected = TodayDeviceHeaderPresentation.make(hasActiveDevice: true, connected: true,
                                                           batteryPct: 64.4)
        XCTAssertEqual(connected.tone, .connected)
        XCTAssertEqual(connected.batteryText, "64%")
        XCTAssertEqual(TodayDeviceHeaderPresentation.make(hasActiveDevice: false, connected: false,
                                                          batteryPct: nil).tone, .unknown)
    }
    #endif
}
