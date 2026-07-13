import XCTest
@testable import WhoopProtocol

final class DataRangeTests: XCTestCase {
    private func hex(_ string: String) -> [UInt8] {
        stride(from: 0, to: string.count, by: 2).map { offset in
            let start = string.index(string.startIndex, offsetBy: offset)
            let end = string.index(start, offsetBy: 2)
            return UInt8(string[start..<end], radix: 16)!
        }
    }

    func testReadsWhoop4NewestAtByteOffset8() {
        let frame = hex("aa100057305d22009968526a083900001d2e2263")
        XCTAssertEqual(DataRange.newestUnix(from: frame, wallNowUnix: 1_783_786_000,
                                            futureSkewSeconds: 48 * 3600), 1_783_785_625)
    }

    func testOldestAlignedScanRejectsSpuriousStraddle() {
        XCTAssertNil(DataRange.oldestUnix(from: hex("aa100057305d22009968526a083900001d2e2263")))
    }
}
