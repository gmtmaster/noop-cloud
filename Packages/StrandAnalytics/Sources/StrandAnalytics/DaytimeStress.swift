import Foundation
import WhoopProtocol

/// A rolling, non-diagnostic physiological-activation proxy.
///
/// Public WHOOP material describes in-the-moment HR/HRV, personal baselines and motion context. A
/// WHOOP-affiliated paper used five-minute moving blocks stepped every 30 seconds. This engine follows
/// that public signal-processing shape without claiming or attempting to reproduce proprietary math.
public enum DaytimeStress {

    /// All behavioural tuning is centralized here so replay experiments can change one value set.
    public struct Configuration: Equatable, Sendable {
        public var windowSeconds = 5 * 60
        public var stepSeconds = 60
        public var minimumHRSamples = 30
        public var minimumWindowCoverage = 0.60
        public var minimumRRIntervals = 20
        public var trimmedFraction = 0.10
        public var minimumHRSpread = 4.0
        public var minimumRMSSDSpread = 8.0
        public var hrWeight = 0.55
        public var hrvWeight = 0.45
        public var motionDeltaFloorG = 0.025
        public var motionDeltaFullG = 0.14
        public var movingHRWeightFloor = 0.20
        public var attackAlpha = 0.48
        public var releaseAlpha = 0.30
        public var maximumStepChange = 0.55
        public var highBandFloor = 2.0
        public var sustainedHighSeconds = 15 * 60
        public var wakingStartHour = 6
        public var wakingEndHour = 22

        public static let `default` = Configuration()
    }

    public static let configuration = Configuration.default
    // Compatibility names retained for callers and older tests.
    public static let minHourHRSamples = configuration.minimumHRSamples
    public static let bucketSeconds = configuration.stepSeconds
    public static let highBandFloor = configuration.highBandFloor
    public static let sustainedHours = configuration.sustainedHighSeconds / configuration.stepSeconds
    public static let wakingStartHour = configuration.wakingStartHour
    public static let wakingEndHour = configuration.wakingEndHour

    public struct ActivityInterval: Equatable, Sendable {
        public let startTs: Int
        public let endTs: Int
        public init(startTs: Int, endTs: Int) { self.startTs = startTs; self.endTs = endTs }
        func overlaps(_ start: Int, _ end: Int) -> Bool { startTs < end && endTs > start }
    }

    /// Kept as `HourPoint` for source compatibility; V2 emits one observation per configured step.
    public struct HourPoint: Equatable, Sendable {
        public let hour: Int
        public let startTs: Int
        public let level: Double?
        public let meanHR: Double?
        public let rmssd: Double?
        public let confidence: Double
        public let motion: Double
        public let isActivity: Bool
        public var hasData: Bool { level != nil }

        public init(hour: Int, startTs: Int, level: Double?, meanHR: Double?, rmssd: Double?,
                    confidence: Double = 1, motion: Double = 0, isActivity: Bool = false) {
            self.hour = hour; self.startTs = startTs; self.level = level
            self.meanHR = meanHR; self.rmssd = rmssd; self.confidence = confidence
            self.motion = motion; self.isActivity = isActivity
        }
    }

    public struct Result: Equatable, Sendable {
        public let hours: [HourPoint]
        public let sustainedHigh: Bool
        /// Number of trailing high-resolution observations, not clock hours.
        public let sustainedRun: Int
        public let dayMean: Double?
        public let peak: HourPoint?
        public init(hours: [HourPoint], sustainedHigh: Bool, sustainedRun: Int,
                    dayMean: Double?, peak: HourPoint?) {
            self.hours = hours; self.sustainedHigh = sustainedHigh; self.sustainedRun = sustainedRun
            self.dayMean = dayMean; self.peak = peak
        }
        public var scored: [HourPoint] { hours.filter { $0.level != nil } }
        public static let empty = Result(hours: [], sustainedHigh: false, sustainedRun: 0,
                                         dayMean: nil, peak: nil)
    }

    private struct Feature {
        let ts: Int
        let hour: Int
        let hr: Double
        let rmssd: Double?
        let confidence: Double
        let motion: Double
        let activity: Bool
    }

    public static func analyze(hr: [HRSample], rr: [RRInterval],
                               gravity: [GravitySample] = [], activities: [ActivityInterval] = [],
                               tzOffsetSeconds: Int = 0,
                               configuration c: Configuration = .default) -> Result {
        guard !hr.isEmpty, c.windowSeconds > 0, c.stepSeconds > 0 else { return .empty }
        let orderedHR = hr.filter { (30...220).contains($0.bpm) }.sorted { $0.ts < $1.ts }
        guard let first = orderedHR.first?.ts, let last = orderedHR.last?.ts else { return .empty }
        let orderedRR = rr.filter { (250...3_000).contains($0.rrMs) }.sorted { $0.ts < $1.ts }
        let orderedGravity = gravity.sorted { $0.ts < $1.ts }

        let firstEnd = ceilDiv(first, c.stepSeconds) * c.stepSeconds
        var features: [Feature] = []
        var h0 = 0, h1 = 0, r0 = 0, r1 = 0, g0 = 0, g1 = 0

        if firstEnd <= last {
            for end in stride(from: firstEnd, through: last, by: c.stepSeconds) {
                let localHour = positiveMod(floorDiv(end + tzOffsetSeconds, 3_600), 24)
                guard localHour >= c.wakingStartHour && localHour < c.wakingEndHour else { continue }
                let start = end - c.windowSeconds
                advance(&h0, orderedHR, while: { $0.ts < start }); h1 = max(h1, h0)
                advance(&h1, orderedHR, while: { $0.ts <= end })
                advance(&r0, orderedRR, while: { $0.ts < start }); r1 = max(r1, r0)
                advance(&r1, orderedRR, while: { $0.ts <= end })
                advance(&g0, orderedGravity, while: { $0.ts < start }); g1 = max(g1, g0)
                advance(&g1, orderedGravity, while: { $0.ts <= end })

                let hrs = orderedHR[h0..<h1]
                guard hrs.count >= c.minimumHRSamples,
                      let lo = hrs.first?.ts, let hi = hrs.last?.ts,
                      Double(hi - lo) / Double(c.windowSeconds) >= c.minimumWindowCoverage else { continue }
                let hrValue = trimmedMean(hrs.map { Double($0.bpm) }, fraction: c.trimmedFraction)
                let rrWindow = Array(orderedRR[r0..<r1])
                let rmssd = rrWindow.count >= c.minimumRRIntervals
                    ? HRVAnalyzer.analyze(rawRR: rrWindow.map { Double($0.rrMs) }).rmssd : nil
                let motion = motionLevel(Array(orderedGravity[g0..<g1]), config: c)
                let activity = activities.contains { $0.overlaps(start, end) }
                let countConfidence = min(1, Double(hrs.count) / Double(max(c.minimumHRSamples * 3, 1)))
                let spanConfidence = min(1, Double(hi - lo) / Double(c.windowSeconds))
                var confidence = 0.45 + 0.30 * countConfidence + 0.25 * spanConfidence
                if rmssd == nil { confidence *= 0.78 }
                features.append(Feature(ts: end, hour: localHour, hr: hrValue, rmssd: rmssd,
                                        confidence: min(max(confidence, 0), 1),
                                        motion: motion, activity: activity))
            }
        }
        guard !features.isEmpty else { return .empty }

        // Robust personal reference from available waking windows. Prefer still/non-workout windows so
        // exercise cannot raise its own baseline; fall back to all valid windows early in the day.
        let still = features.filter { $0.motion < 0.35 && !$0.activity }
        let reference = still.count >= 4 ? still : features
        let hrValues = reference.map(\.hr)
        let rrValues = reference.compactMap(\.rmssd)
        let hrMedian = median(hrValues)
        let rrMedian = rrValues.isEmpty ? nil : median(rrValues)
        let hrSpread = max(robustSpread(hrValues), c.minimumHRSpread)
        let rrSpread = max(robustSpread(rrValues), c.minimumRMSSDSpread)

        var points: [HourPoint] = []
        var previous: Double?
        var previousTs: Int?
        for f in features {
            let hrZ = clamp((f.hr - hrMedian) / hrSpread, -3, 3)
            let rrZ = (f.rmssd != nil && rrMedian != nil)
                ? clamp((rrMedian! - f.rmssd!) / rrSpread, -3, 3) : 0
            let motionContext = max(f.motion, f.activity ? 1 : 0)
            let hrSpecificity = 1 - motionContext * (1 - c.movingHRWeightFloor)
            let availableHRVWeight = f.rmssd == nil ? 0 : c.hrvWeight
            // Keep the full configured denominator. Otherwise an HR-only window would divide away the
            // motion attenuation and moving HR would remain just as influential as still HR.
            let weightSum = max(0.0001, c.hrWeight + c.hrvWeight)
            let evidence = (c.hrWeight * hrSpecificity * hrZ + availableHRVWeight * rrZ) / weightSum
            let raw = squash(evidence)
            // Low confidence shrinks toward the neutral midpoint instead of increasing volatility.
            let credible = 1.5 + (raw - 1.5) * f.confidence
            let value: Double
            if let old = previous, let oldTs = previousTs, f.ts - oldTs <= c.stepSeconds * 2 {
                let alpha = credible >= old ? c.attackAlpha : c.releaseAlpha
                let ema = old + alpha * (credible - old)
                value = old + clamp(ema - old, -c.maximumStepChange, c.maximumStepChange)
            } else { value = credible }
            previous = value; previousTs = f.ts
            points.append(HourPoint(hour: f.hour, startTs: f.ts, level: value, meanHR: f.hr,
                                    rmssd: f.rmssd, confidence: f.confidence,
                                    motion: f.motion, isActivity: f.activity))
        }

        var run = 0
        for p in points.reversed() {
            if (p.level ?? 0) >= c.highBandFloor { run += 1 } else { break }
        }
        let needed = Int(ceil(Double(c.sustainedHighSeconds) / Double(c.stepSeconds)))
        return Result(hours: points, sustainedHigh: run >= needed, sustainedRun: run,
                      dayMean: mean(points.compactMap(\.level)),
                      peak: points.max { ($0.level ?? 0) < ($1.level ?? 0) })
    }

    static func squash(_ raw: Double) -> Double { clamp(3 / (1 + exp(-raw)), 0, 3) }
    static func mean(_ xs: [Double]) -> Double? { xs.isEmpty ? nil : xs.reduce(0, +) / Double(xs.count) }
    static func median(_ xs: [Double]) -> Double {
        let s = xs.sorted(), m = s.count / 2
        guard !s.isEmpty else { return 0 }
        return s.count.isMultiple(of: 2) ? (s[m - 1] + s[m]) / 2 : s[m]
    }
    static func robustSpread(_ xs: [Double]) -> Double {
        guard xs.count >= 4 else { return 0 }
        let s = xs.sorted()
        return (quantile(s, 0.75) - quantile(s, 0.25)) / 1.349
    }
    static func trimmedMean(_ xs: [Double], fraction: Double) -> Double {
        let s = xs.sorted(), trim = min(Int(Double(s.count) * max(0, fraction)), max(0, (s.count - 1) / 2))
        let kept = s[trim..<(s.count - trim)]
        return kept.reduce(0, +) / Double(kept.count)
    }
    static func motionLevel(_ samples: [GravitySample], config c: Configuration) -> Double {
        guard samples.count >= 3 else { return 0 }
        var deltas: [Double] = []; deltas.reserveCapacity(samples.count - 1)
        for pair in zip(samples, samples.dropFirst()) {
            let dx = pair.1.x - pair.0.x, dy = pair.1.y - pair.0.y, dz = pair.1.z - pair.0.z
            deltas.append(sqrt(dx * dx + dy * dy + dz * dz))
        }
        let typical = median(deltas)
        return clamp((typical - c.motionDeltaFloorG) / max(0.0001, c.motionDeltaFullG - c.motionDeltaFloorG), 0, 1)
    }
    static func quantile(_ sorted: [Double], _ q: Double) -> Double {
        guard !sorted.isEmpty else { return 0 }; if sorted.count == 1 { return sorted[0] }
        let p = q * Double(sorted.count - 1), lo = Int(p), hi = min(lo + 1, sorted.count - 1)
        return sorted[lo] + (p - Double(lo)) * (sorted[hi] - sorted[lo])
    }
    static func floorDiv(_ a: Int, _ b: Int) -> Int { let q = a / b, r = a % b; return (r != 0 && (r < 0) != (b < 0)) ? q - 1 : q }
    static func ceilDiv(_ a: Int, _ b: Int) -> Int { -floorDiv(-a, b) }
    static func positiveMod(_ a: Int, _ b: Int) -> Int { let r = a % b; return r >= 0 ? r : r + b }
    static func clamp(_ x: Double, _ lo: Double, _ hi: Double) -> Double { min(max(x, lo), hi) }
    static func advance<T>(_ index: inout Int, _ values: [T], while predicate: (T) -> Bool) {
        while index < values.count && predicate(values[index]) { index += 1 }
    }
}
