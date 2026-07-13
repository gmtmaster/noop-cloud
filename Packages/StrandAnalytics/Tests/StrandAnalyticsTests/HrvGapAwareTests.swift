import XCTest
@testable import StrandAnalytics

final class HrvGapAwareTests: XCTestCase {
    func testRangeDropDoesNotSpliceNeighbours() {
        let raw = Array(repeating: 800.0, count: 10) + [3000, 1000] + Array(repeating: 800.0, count: 10)
        let cleaned = HRVAnalyzer.cleanRRGapAware(raw)
        XCTAssertEqual(cleaned.nn, HRVAnalyzer.cleanRR(raw))
        XCTAssertFalse(cleaned.contiguous[10])
        XCTAssertEqual(HRVAnalyzer.rmssdGapAware(cleaned.nn, cleaned.contiguous)!, 0, accuracy: 0.0001)
        XCTAssertEqual(HRVAnalyzer.pnn50GapAware(cleaned.nn, cleaned.contiguous)!, 0, accuracy: 0.0001)
    }

    func testNoDropMatchesPlainRmssd() {
        let raw = [800.0, 820, 790, 810, 805]
        let cleaned = HRVAnalyzer.cleanRRGapAware(raw)
        XCTAssertEqual(HRVAnalyzer.rmssdGapAware(cleaned.nn, cleaned.contiguous)!,
                       HRVAnalyzer.rmssdRaw(cleaned.nn)!, accuracy: 0.0001)
    }
}
