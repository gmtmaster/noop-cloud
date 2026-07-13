import XCTest
import WhoopStore

/// #715 — merging imported + computed sleep must preserve EVERY session. The old per-day dictionary
/// (`[String: CachedSleepSession]`) overwrote on collision, so a day with two sessions (a main night
/// and a nap, or two nights) silently lost one in both the app and the CSV export.
final class SleepMergeTests: XCTestCase {

    private func session(start: Int, end: Int, stages: String? = nil) -> CachedSleepSession {
        CachedSleepSession(startTs: start, endTs: end, efficiency: nil,
                           restingHr: nil, avgHrv: nil, stagesJSON: stages)
    }
    // Deterministic "local day" keyer for the tests (real callers pass their tz-aware keyer).
    private let dayKey: (CachedSleepSession) -> String = { String($0.endTs / 86_400) }

    func testTwoComputedSessionsSameEndDayBothSurvive() {
        let night = session(start: 0, end: 8 * 3600)            // ends day 0
        let nap   = session(start: 14 * 3600, end: 15 * 3600)   // ALSO ends day 0
        let merged = SleepMerge.merge(imported: [], computed: [night, nap], endDay: dayKey)
        XCTAssertEqual(merged.count, 2, "both same-end-day sessions must survive")
        XCTAssertEqual(merged.map(\.startTs), [0, 14 * 3600], "sorted by start")
    }

    func testTwoImportedSessionsSameEndDayBothSurvive() {
        let a = session(start: 0, end: 8 * 3600)
        let b = session(start: 14 * 3600, end: 15 * 3600)
        let merged = SleepMerge.merge(imported: [a, b], computed: [], endDay: dayKey)
        XCTAssertEqual(merged.count, 2)
    }

    func testImportedWinsForItsDayButKeepsComputedOnOtherDays() {
        let compDay0 = session(start: 0, end: 8 * 3600)                 // day 0
        let compDay1 = session(start: 86_400, end: 86_400 + 8 * 3600)   // day 1
        let impDay0  = session(start: 3600, end: 8 * 3600 + 1800)       // day 0, imported
        let merged = SleepMerge.merge(imported: [impDay0], computed: [compDay0, compDay1], endDay: dayKey)
        XCTAssertEqual(merged.count, 2)
        XCTAssertTrue(merged.contains { $0.startTs == 3600 }, "imported day-0 session kept")
        XCTAssertFalse(merged.contains { $0.startTs == 0 }, "computed day-0 session yields to imported")
        XCTAssertTrue(merged.contains { $0.startTs == 86_400 }, "computed day-1 session untouched")
    }

    func testEmptyInputsReturnEmpty() {
        XCTAssertTrue(SleepMerge.merge(imported: [], computed: [], endDay: dayKey).isEmpty)
    }

    func testComputedStagesSurviveStageLessImport() {
        let computed = session(start: 0, end: 8 * 3600,
                               stages: #"[{"start":0,"end":100,"stage":"light"}]"#)
        let imported = session(start: 3600, end: 8 * 3600 + 1800)
        let merged = SleepMerge.merge(imported: [imported], computed: [computed], endDay: dayKey)
        XCTAssertEqual(merged.map(\.startTs), [0])
    }

    func testImportedStagesStillWin() {
        let stages = #"[{"start":0,"end":100,"stage":"light"}]"#
        let computed = session(start: 0, end: 8 * 3600, stages: stages)
        let imported = session(start: 3600, end: 8 * 3600 + 1800, stages: stages)
        let merged = SleepMerge.merge(imported: [imported], computed: [computed], endDay: dayKey)
        XCTAssertEqual(merged.map(\.startTs), [3600])
    }
}
