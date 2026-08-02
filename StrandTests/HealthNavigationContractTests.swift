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
}
