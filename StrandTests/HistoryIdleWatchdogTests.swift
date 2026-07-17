import XCTest
@testable import Strand

final class HistoryIdleWatchdogTests: XCTestCase {
    func testTimeoutFiresOnlyWhenRadioAndProcessingAreIdle() {
        XCTAssertTrue(HistoryIdleWatchdog.shouldTimeout(isProcessing: false, queueDepth: 0))
        XCTAssertFalse(HistoryIdleWatchdog.shouldTimeout(isProcessing: true, queueDepth: 0))
        XCTAssertFalse(HistoryIdleWatchdog.shouldTimeout(isProcessing: false, queueDepth: 1))
        XCTAssertFalse(HistoryIdleWatchdog.shouldTimeout(isProcessing: true, queueDepth: 500))
    }
}
