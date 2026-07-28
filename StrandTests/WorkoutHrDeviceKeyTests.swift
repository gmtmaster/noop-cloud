import XCTest
@testable import Strand

final class WorkoutHrDeviceKeyTests: XCTestCase {
    func testDetectedWorkoutReadsItsRecordingStrap() {
        XCTAssertEqual(
            Repository.workoutHrDeviceId(source: "whoop-aabbcc-noop", activeStrapId: "my-whoop"),
            "whoop-aabbcc")
    }

    func testManualAndImportedWorkoutsReadTheActiveStrap() {
        for source in ["manual", "apple-health", "activity-file", "lifting", "my-whoop"] {
            XCTAssertEqual(
                Repository.workoutHrDeviceId(source: source, activeStrapId: "whoop-aabbcc"),
                "whoop-aabbcc")
        }
    }
}
