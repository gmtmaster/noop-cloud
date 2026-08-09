import XCTest
@testable import StrandAnalytics
import WhoopProtocol

final class HRArtifactFilterTests: XCTestCase {
    private let maxHR = 190.0
    private let rest = 60.0

    private func samples(_ bpms: [Int], step: Int = 1) -> [HRSample] {
        bpms.enumerated().map { HRSample(ts: $0.offset * step, bpm: $0.element) }
    }

    private func effort(_ hr: [HRSample]) -> Double {
        StrainScorer.strain(hr, maxHR: maxHR, restingHR: rest) ?? 0
    }

    func testIsolatedExtremeSpikeIsRemovedAndNoLongerCreatesEffort() {
        var hr = Array(repeating: 75, count: 600)
        hr[300] = 190
        let raw = samples(hr)
        let filtered = HRArtifactFilter.filteringShortSpikes(raw)

        XCTAssertEqual(filtered.count, raw.count)
        XCTAssertGreaterThan(effort(raw), 0)
        XCTAssertEqual(effort(filtered), 0)
    }

    func testSeveralSecondSpikeIsRemoved() {
        let raw = samples(Array(repeating: 80, count: 300)
            + Array(repeating: 175, count: 6)
            + Array(repeating: 82, count: 300))
        let filtered = HRArtifactFilter.filteringShortSpikes(raw)

        XCTAssertEqual(filtered.filter { $0.bpm >= 170 }.count, 0)
        XCTAssertGreaterThan(effort(raw), effort(filtered))
        XCTAssertEqual(effort(filtered), 0)
    }

    func testGenuineGradualExerciseRiseRemainsUnchanged() {
        let ramp = Array(repeating: 90, count: 150)
            + stride(from: 90, through: 165, by: 3).flatMap { Array(repeating: $0, count: 3) }
            + Array(repeating: 165, count: 400)
        let raw = samples(ramp)
        let filtered = HRArtifactFilter.filteringShortSpikes(raw)

        XCTAssertEqual(filtered, raw)
        XCTAssertEqual(effort(filtered), effort(raw))
    }

    func testSustainedHighHRRemainsUnchanged() {
        let raw = samples(Array(repeating: 75, count: 100)
            + Array(repeating: 175, count: 400)
            + Array(repeating: 80, count: 100))
        let filtered = HRArtifactFilter.filteringShortSpikes(raw)

        XCTAssertEqual(filtered, raw)
        XCTAssertEqual(effort(filtered), effort(raw))
    }

    func testIntervalStyleChangesRemainUnchanged() {
        var bpms = Array(repeating: 90, count: 100)
        for _ in 0..<5 {
            bpms += Array(repeating: 165, count: 30)
            bpms += Array(repeating: 105, count: 30)
        }
        bpms += Array(repeating: 90, count: 200)
        let raw = samples(bpms)
        let filtered = HRArtifactFilter.filteringShortSpikes(raw)

        XCTAssertEqual(filtered, raw)
        XCTAssertEqual(effort(filtered), effort(raw))
    }

    func testSparseBracketedSpikeCannotInheritThirtySecondsOfStrain() {
        let raw = (0..<30).map { i in HRSample(ts: i * 30, bpm: i == 15 ? 190 : 75) }
        let filtered = HRArtifactFilter.filteringShortSpikes(raw)

        XCTAssertEqual(filtered.count, raw.count)
        XCTAssertGreaterThan(effort(raw), 0)
        XCTAssertEqual(effort(filtered), 0)
    }

    func testDailyEngineUsesFilteredStreamForBothEffortAndCalories() {
        let clean = samples(Array(repeating: 75, count: 600))
        var artifact = clean
        artifact[300] = HRSample(ts: 300, bpm: 190)
        let profile = UserProfile(weightKg: 70, heightCm: 175, age: 30, sex: "male")

        let cleanDay = AnalyticsEngine.analyzeDay(day: "1970-01-01", dayHr: clean,
                                                   profile: profile, maxHROverride: maxHR)
        let artifactDay = AnalyticsEngine.analyzeDay(day: "1970-01-01", dayHr: artifact,
                                                      profile: profile, maxHROverride: maxHR)

        XCTAssertEqual(artifactDay.strain, cleanDay.strain)
        XCTAssertEqual(artifactDay.daily.activeKcalEst, cleanDay.daily.activeKcalEst)
    }

    func testAug8SpikeShapeCanonicalAndLiveCalculationsAgreeWithoutMutatingRawHR() throws {
        let start = 1_786_140_000
        var raw = (0..<1_800).map { HRSample(ts: start + $0, bpm: 132) }
        // Brief bracketed optical island embedded in otherwise genuine sustained activity.
        for i in 900..<907 { raw[i] = HRSample(ts: start + i, bpm: 190) }
        let original = raw
        let profile = UserProfile(weightKg: 70, heightCm: 175, age: 30, sex: "male")

        let filtered = HRArtifactFilter.filteringShortSpikes(raw)
        let live = try XCTUnwrap(StrainScorer.strain(filtered, maxHR: maxHR,
                                                     restingHR: rest, sex: profile.sex))
        let canonical = AnalyticsEngine.analyzeDay(day: "2026-08-08", dayHr: raw,
                                                    profile: profile, maxHROverride: maxHR)
        let canonicalStrain = try XCTUnwrap(canonical.strain)
        let persistedStrain = try XCTUnwrap(canonical.daily.strain)

        XCTAssertEqual(canonicalStrain, live, accuracy: 0.000_001)
        XCTAssertEqual(persistedStrain, live, accuracy: 0.000_001)
        XCTAssertEqual(raw, original, "artifact rejection must never mutate durable raw HR")
        XCTAssertLessThan(live, try XCTUnwrap(StrainScorer.strain(raw, maxHR: maxHR,
                                                                  restingHR: rest, sex: profile.sex)))
    }
}
