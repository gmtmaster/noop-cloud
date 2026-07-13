import XCTest
import WhoopProtocol
@testable import StrandAnalytics

final class SleepStagerHrConfirmTests: XCTestCase {
    private let start = 1_000_000

    private func samples(base: Int, spikes: Int = 0) -> [HRSample] {
        (0..<600).map { HRSample(ts: start + $0, bpm: $0 < spikes ? 190 : base) }
    }

    private var period: SleepStager.Period {
        SleepStager.Period(stage: "sleep", start: start, end: start + 600)
    }

    func testSpikySleepUsesMedianAndSurvives() {
        XCTAssertTrue(SleepStager.confirmSleepWithHR(period, hr: samples(base: 48, spikes: 30), baseline: 50))
    }

    func testElevatedRunStillFails() {
        XCTAssertFalse(SleepStager.confirmSleepWithHR(period, hr: samples(base: 60), baseline: 50))
    }
}
