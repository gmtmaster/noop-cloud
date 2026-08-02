import XCTest
@testable import StrandAnalytics

final class StressPresentationTests: XCTestCase {
    private let base = Date(timeIntervalSince1970: 1_700_000_000)

    private func point(_ offset: Int, _ value: Double?) -> DaytimeStress.HourPoint {
        .init(hour: 6 + offset / 3600, startTs: Int(base.timeIntervalSince1970) + offset,
              level: value, meanHR: nil, rmssd: nil)
    }

    func testSamplesAreOrderedDeduplicatedAndClamped() {
        let samples = StressPresentation.samples(from: [point(3600, 1), point(0, -2), point(3600, 4)])
        XCTAssertEqual(samples.map(\.value), [0, 3])
        XCTAssertLessThan(samples[0].timestamp, samples[1].timestamp)
    }

    func testThresholdEdgesAreDeterministic() {
        XCTAssertEqual(StressPresentation.Zone(score: 0.999), .low)
        XCTAssertEqual(StressPresentation.Zone(score: 1), .medium)
        XCTAssertEqual(StressPresentation.Zone(score: 1.999), .medium)
        XCTAssertEqual(StressPresentation.Zone(score: 2), .high)
    }

    func testIntervalsAreCappedAndMissingIsNotLow() {
        let day = StressPresentation.summarize(date: base, points: [point(0, 0.5), point(10 * 3600, 2.5)])
        XCTAssertEqual(day.distribution.low, 3600)
        XCTAssertEqual(day.distribution.high, 3600)
        XCTAssertEqual(day.distribution.observed, 7200)
        XCTAssertEqual(day.distribution.coverage, 0.125, accuracy: 0.0001)
    }

    func testCurrentPartialBucketIsClipped() {
        let day = StressPresentation.summarize(date: base, points: [point(0, 1.5)],
                                               end: base.addingTimeInterval(900))
        XCTAssertEqual(day.distribution.medium, 900)
    }

    func testNearestSampleSelectsRecordedPoint() {
        let samples = StressPresentation.samples(from: [point(0, 1), point(3600, 2)])
        XCTAssertEqual(StressPresentation.nearestSample(to: base.addingTimeInterval(3000), in: samples)?.value, 2)
    }

    func testStaleness() {
        let sample = StressPresentation.Sample(timestamp: base, value: 1)
        XCTAssertFalse(StressPresentation.isStale(sample, now: base.addingTimeInterval(89 * 60)))
        XCTAssertTrue(StressPresentation.isStale(sample, now: base.addingTimeInterval(91 * 60)))
    }

    func testBaselineExcludesSelectedFutureSparseAndUsesMedian() {
        func day(_ daysAgo: Int, low: Double, coverage: Double = 1) -> StressPresentation.Day {
            let date = base.addingTimeInterval(Double(-daysAgo) * 86400)
            let observed = StressPresentation.expectedDayDuration * coverage
            let distribution = StressPresentation.Distribution(
                low: observed * low, medium: observed * (1 - low), high: 0,
                observed: observed, coverage: coverage)
            return .init(date: date, samples: [], distribution: distribution)
        }
        let result = StressPresentation.baseline(selectedDate: base, candidates: [
            day(7, low: 0.6), day(14, low: 0.7), day(21, low: 0.8),
            day(28, low: 0.0), day(35, low: 1, coverage: 0.2),
            day(-7, low: 1), day(0, low: 1)
        ])
        XCTAssertEqual(result?.validDayCount, 4)
        XCTAssertEqual(result?.lowProportion ?? 0, 0.65, accuracy: 0.0001)
    }

    func testBaselineRequiresThreeQualifiedDays() {
        let distribution = StressPresentation.Distribution(low: 40000, medium: 0, high: 0,
                                                           observed: 40000, coverage: 0.7)
        let days = (1...2).map { StressPresentation.Day(date: base.addingTimeInterval(Double(-$0) * 86400),
                                                        samples: [], distribution: distribution) }
        XCTAssertNil(StressPresentation.baseline(selectedDate: base, candidates: days))
    }
}
