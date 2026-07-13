import XCTest
@testable import Strand

@MainActor
final class SourceCandidatesOrderTests: XCTestCase {
    func testCanonicalImportOutranksComputedSiblingsAfterReAdd() {
        let candidates = Repository.sourceCandidates(forKey: "rhr", preferredSource: "my-whoop",
                                                      actualWhoopSource: "whoop-4A0B")
        XCTAssertEqual(candidates.map(\.source),
                       ["whoop-4A0B", "my-whoop", "whoop-4A0B-noop", "my-whoop-noop", "apple-health"])
    }
}
