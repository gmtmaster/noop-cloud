import Foundation

/// Presentation-only analysis for the Stress Monitor. It consumes the existing
/// `DaytimeStress` output and never changes how a stress score is calculated.
public enum StressPresentation {
    public static let scale: ClosedRange<Double> = 0...3
    public static let expectedDayDuration: TimeInterval = 16 * 60 * 60
    public static let maximumAttributedInterval: TimeInterval = 60 * 60
    public static let qualifiedCoverage = 0.60
    public static let maximumBaselineDays = 8
    public static let minimumBaselineDays = 3
    public static let staleAfter: TimeInterval = 90 * 60

    public enum Zone: String, CaseIterable, Codable, Sendable {
        case low, medium, high

        public init(score: Double) {
            if score < 1 { self = .low }
            else if score < 2 { self = .medium }
            else { self = .high }
        }
    }

    public struct Sample: Equatable, Sendable {
        public let timestamp: Date
        public let value: Double

        public init(timestamp: Date, value: Double) {
            self.timestamp = timestamp
            self.value = min(max(value, scale.lowerBound), scale.upperBound)
        }
    }

    public struct Distribution: Equatable, Sendable {
        public let low: TimeInterval
        public let medium: TimeInterval
        public let high: TimeInterval
        public let observed: TimeInterval
        public let coverage: Double

        public init(low: TimeInterval, medium: TimeInterval, high: TimeInterval,
                    observed: TimeInterval, coverage: Double) {
            self.low = low; self.medium = medium; self.high = high
            self.observed = observed; self.coverage = coverage
        }

        public func duration(for zone: Zone) -> TimeInterval {
            switch zone { case .low: low; case .medium: medium; case .high: high }
        }

        public func proportion(for zone: Zone) -> Double {
            guard observed > 0 else { return 0 }
            return duration(for: zone) / observed
        }
    }

    public struct Day: Equatable, Sendable {
        public let date: Date
        public let samples: [Sample]
        public let distribution: Distribution
        public var latest: Sample? { samples.last }

        public init(date: Date, samples: [Sample], distribution: Distribution) {
            self.date = date; self.samples = samples; self.distribution = distribution
        }
    }

    public struct Baseline: Equatable, Sendable {
        public let validDayCount: Int
        public let lowProportion: Double
        public let mediumProportion: Double
        public let highProportion: Double
        public var isQualified: Bool { validDayCount >= minimumBaselineDays }

        public func proportion(for zone: Zone) -> Double {
            switch zone { case .low: lowProportion; case .medium: mediumProportion; case .high: highProportion }
        }
    }

    public static func samples(from points: [DaytimeStress.HourPoint]) -> [Sample] {
        var byTimestamp: [Int: Double] = [:]
        for point in points where point.level?.isFinite == true {
            byTimestamp[point.startTs] = point.level
        }
        return byTimestamp.keys.sorted().compactMap { ts in
            byTimestamp[ts].map { Sample(timestamp: Date(timeIntervalSince1970: TimeInterval(ts)), value: $0) }
        }
    }

    /// Each scored hourly bucket owns at most one hour. A following sample never
    /// causes a long missing gap to be assigned to the preceding zone.
    public static func summarize(date: Date, points: [DaytimeStress.HourPoint],
                                 end: Date? = nil) -> Day {
        let ordered = samples(from: points)
        var totals: [Zone: TimeInterval] = [:]
        for (index, sample) in ordered.enumerated() {
            let naturalEnd = sample.timestamp.addingTimeInterval(maximumAttributedInterval)
            let next = index + 1 < ordered.count ? ordered[index + 1].timestamp : naturalEnd
            let clippedEnd = min(next, naturalEnd, end ?? naturalEnd)
            let duration = max(0, clippedEnd.timeIntervalSince(sample.timestamp))
            totals[Zone(score: sample.value), default: 0] += duration
        }
        let observed = totals.values.reduce(0, +)
        let distribution = Distribution(
            low: totals[.low, default: 0], medium: totals[.medium, default: 0],
            high: totals[.high, default: 0], observed: observed,
            coverage: min(max(observed / expectedDayDuration, 0), 1))
        return Day(date: date, samples: ordered, distribution: distribution)
    }

    public static func nearestSample(to date: Date, in samples: [Sample]) -> Sample? {
        samples.min { abs($0.timestamp.timeIntervalSince(date)) < abs($1.timestamp.timeIntervalSince(date)) }
    }

    public static func isStale(_ sample: Sample?, now: Date) -> Bool {
        guard let sample else { return true }
        return now.timeIntervalSince(sample.timestamp) > staleAfter
    }

    /// Caller supplies prior matching weekdays only. The engine still enforces
    /// selected-date exclusion, no-look-ahead, coverage, recency and robust medians.
    public static func baseline(selectedDate: Date, candidates: [Day]) -> Baseline? {
        let eligible = candidates
            .filter { $0.date < selectedDate && $0.distribution.coverage >= qualifiedCoverage }
            .sorted { $0.date > $1.date }
            .prefix(maximumBaselineDays)
        guard eligible.count >= minimumBaselineDays else { return nil }
        func median(_ values: [Double]) -> Double {
            let sorted = values.sorted(), middle = sorted.count / 2
            return sorted.count.isMultiple(of: 2)
                ? (sorted[middle - 1] + sorted[middle]) / 2 : sorted[middle]
        }
        let days = Array(eligible)
        return Baseline(validDayCount: days.count,
                        lowProportion: median(days.map { $0.distribution.proportion(for: .low) }),
                        mediumProportion: median(days.map { $0.distribution.proportion(for: .medium) }),
                        highProportion: median(days.map { $0.distribution.proportion(for: .high) }))
    }
}
