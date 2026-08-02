import XCTest
@testable import Strand

final class HealthNavigationContractTests: XCTestCase {
    func testHealthReplacesTrendsInPrimaryTabs() {
        XCTAssertEqual(HealthNavigationContract.primaryTabs,
                       ["Today", "Health", "Friends", "More"])
        XCTAssertEqual(HealthNavigationContract.healthTabIndex, 1)
        XCTAssertTrue(HealthNavigationContract.sleepIsContextual)
        XCTAssertFalse(HealthNavigationContract.primaryTabs.contains("Sleep"))
        XCTAssertFalse(HealthNavigationContract.primaryTabs.contains("Trends"))
    }

    func testTrendsRemainsASecondaryDestination() {
        XCTAssertTrue(HealthNavigationContract.trendsRemainsSecondary)
        XCTAssertTrue(NavItem.allCases.contains(.trends))
    }

    func testTonightSleepDistinguishesAlarmAndWakeTarget() {
        XCTAssertEqual(TonightSleepWakeState.activeAlarm.label, "ALARM ON")
        XCTAssertEqual(TonightSleepWakeState.wakeTarget.label, "WAKE TARGET")
        XCTAssertEqual(TonightSleepWakeState.notSet.label, "Not set")
    }

    func testHistoricalTonightSleepCannotEditAlarm() {
        XCTAssertFalse(TonightSleepWakeState.historical.canEditAlarm)
        XCTAssertTrue(TonightSleepWakeState.activeAlarm.canEditAlarm)
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

    func testOrbGeometryUsesOneCenterAndBoundedRadiusFamily() {
        for side in [280.0, 330.0, 430.0] {
            let geometry = HealthspanOrbGeometry(size: CGSize(width: side, height: side))
            XCTAssertEqual(geometry.center, CGPoint(x: side / 2, y: side / 2))
            XCTAssertEqual(geometry.baseRadius, side * HealthspanOrbGeometry.baseRadiusFactor,
                           accuracy: 0.0001)
            XCTAssertEqual(geometry.coreRadius(scale: 1),
                           geometry.baseRadius * HealthspanOrbGeometry.coreRadiusFactor, accuracy: 0.0001)
            XCTAssertEqual(geometry.particleRadius(scale: 1),
                           geometry.baseRadius * HealthspanOrbGeometry.particleRadiusFactor, accuracy: 0.0001)
            XCTAssertTrue(geometry.containsAllLayers(scale: 1.012))
            XCTAssertEqual(geometry.project(normalizedX: 0, normalizedY: 0, scale: 1), geometry.center)

            let left = geometry.project(normalizedX: -0.5, normalizedY: 0, scale: 1)
            let right = geometry.project(normalizedX: 0.5, normalizedY: 0, scale: 1)
            XCTAssertEqual(left.x + right.x, geometry.center.x * 2, accuracy: 0.0001)
        }
    }

    func testParticleDriftIsPeriodicAndZeroMean() {
        let index = 11
        let speed = HealthspanOrbMotion.particleAngularSpeed(index: index)
        let samples = 360
        let xMean = (0..<samples).map { i in
            HealthspanOrbMotion.particle(index: index,
                elapsed: Double(i) / Double(samples) * (2 * .pi / speed)).xDrift
        }.reduce(0, +) / Double(samples)
        let yMean = (0..<samples).map { i in
            HealthspanOrbMotion.particle(index: index,
                elapsed: Double(i) / Double(samples) * (2 * .pi / (speed * 0.73))).yDrift
        }.reduce(0, +) / Double(samples)
        XCTAssertEqual(xMean, 0, accuracy: 0.000_001)
        XCTAssertEqual(yMean, 0, accuracy: 0.000_001)
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
