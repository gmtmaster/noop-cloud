import Foundation

public enum NoopAgeConfidence: String, Equatable, Sendable {
    case insufficient, calibrating, developing, established
}

public enum NoopAgeImpact: String, Equatable, Sendable { case helping, holdingBack }
public enum NoopAgeDomain: String, CaseIterable, Equatable, Sendable { case sleep, activity, fitness, body }

public struct NoopAgeContributor: Equatable, Sendable {
    public let key: String
    public let label: String
    public let domain: NoopAgeDomain
    public let adjustmentYears: Double
    public let recentAdjustmentYears: Double?
    public var impact: NoopAgeImpact { (recentAdjustmentYears ?? adjustmentYears) <= 0 ? .helping : .holdingBack }
    public init(key: String, label: String, domain: NoopAgeDomain, adjustmentYears: Double,
                recentAdjustmentYears: Double? = nil) {
        self.key = key; self.label = label; self.domain = domain
        self.adjustmentYears = adjustmentYears; self.recentAdjustmentYears = recentAdjustmentYears
    }
}

/// One local-day observation. Nil means unavailable, never zero. Sleep timing is minutes from local
/// midnight and is supplied only for a real main sleep. Activity minutes are real recorded values.
public struct HealthspanDay: Equatable, Sendable {
    public let day: String
    public var sleepMinutes: Double?, sleepStartMinute: Double?, wakeMinute: Double?
    public var steps: Double?, zone1to3Minutes: Double?, zone4to5Minutes: Double?, strengthMinutes: Double?
    public var restingHR: Double?, vo2Max: Double?, leanMassPercent: Double?
    public init(day: String, sleepMinutes: Double? = nil, sleepStartMinute: Double? = nil,
                wakeMinute: Double? = nil, steps: Double? = nil, zone1to3Minutes: Double? = nil,
                zone4to5Minutes: Double? = nil, strengthMinutes: Double? = nil,
                restingHR: Double? = nil, vo2Max: Double? = nil, leanMassPercent: Double? = nil) {
        self.day = day; self.sleepMinutes = sleepMinutes; self.sleepStartMinute = sleepStartMinute
        self.wakeMinute = wakeMinute; self.steps = steps; self.zone1to3Minutes = zone1to3Minutes
        self.zone4to5Minutes = zone4to5Minutes; self.strengthMinutes = strengthMinutes
        self.restingHR = restingHR; self.vo2Max = vo2Max; self.leanMassPercent = leanMassPercent
    }
}

public struct NoopAgeCoverage: Equatable, Sendable {
    public let calendarDays, validWearDays, sleepNights, rhrDays, activityDays, validWeeks: Int
    public let representedDomains: Int
    public let missingProportion: Double
    public let unavailableContributorKeys: [String]
}

public struct NoopAgeWeekResult: Equatable, Sendable {
    public let weekEndDay: String
    public let rawAge: Double?, noopAge: Double?, paceOfAging: Double?
    public let confidence: NoopAgeConfidence
    public let contributors: [NoopAgeContributor]
    public let ageContributors: [NoopAgeContributor]
    public let coverage: NoopAgeCoverage
    public let modelVersion: String
}

/// Canonical, deterministic Healthspan model. WHOOP's production coefficients and covariance correction
/// are proprietary; v2 is NOOP's transparent approximation of its published effective-age architecture.
public enum NoopAgeEngine {
    public enum Configuration {
        public static let modelVersion = "noop-healthspan-v2"
        public static let longTermDays = 180, recentDays = 30
        public static let minimumRecentPaceWearDays = 21
        public static let minimumOlderPaceWearDays = 28
        public static let minimumPaceWeeks = 8
        public static let minimumPaceDomains = 2
        public static let recencyHalfLifeDays = 75.0
        public static let minimumPace = -1.0, maximumPace = 3.0
        public static let lnHazardPerYear = log(1.10)
        public static let domainOverlapShrink = 0.82
        public static let maximumTotalAdjustmentYears = 10.0
    }

    /// The exact, inspectable coverage gates behind Pace of Aging. Counts are scoped to a completed
    /// weekly cutoff: `recentWearDays` is inside the trailing 30 calendar days, while `olderWearDays`
    /// is strictly before that window. A wear day has evidence from at least two of sleep, RHR and
    /// activity. Weeks count only when they contain at least one such wear day.
    public struct PaceEligibility: Equatable, Sendable {
        public let recentWearDays: Int
        public let olderWearDays: Int
        public let validWeeks: Int
        public let recentDomains: Int
        public let olderDomains: Int
        public init(recentWearDays: Int, olderWearDays: Int, validWeeks: Int,
                    recentDomains: Int, olderDomains: Int) {
            self.recentWearDays = recentWearDays; self.olderWearDays = olderWearDays
            self.validWeeks = validWeeks; self.recentDomains = recentDomains
            self.olderDomains = olderDomains
        }
        public var isEligible: Bool {
            recentWearDays >= Configuration.minimumRecentPaceWearDays &&
            olderWearDays >= Configuration.minimumOlderPaceWearDays &&
            validWeeks >= Configuration.minimumPaceWeeks &&
            recentDomains >= Configuration.minimumPaceDomains &&
            olderDomains >= Configuration.minimumPaceDomains
        }
    }

    /// The canonical projection consumed by Today/Healthspan directly and persisted for Trends.
    /// Legacy fitness_age/body_age/vitality keys are intentionally never emitted here.
    public static func canonicalMetricValues(_ result: NoopAgeWeekResult) -> [String: Double] {
        var values: [String: Double] = [:]
        if let age = result.noopAge { values["noop_age"] = age }
        if let pace = result.paceOfAging { values["noop_pace"] = pace }
        return values
    }

    public static func evaluate(days: [HealthspanDay], weekEndDays: [String],
                                chronologicalAge: @Sendable (String) -> Double?) -> [NoopAgeWeekResult] {
        let sorted = days.sorted { $0.day < $1.day }
        var results: [NoopAgeWeekResult] = []
        for cutoff in weekEndDays.sorted() {
            guard let age = chronologicalAge(cutoff), age >= 18 else {
                results.append(empty(cutoff)); continue
            }
            let prefix = sorted.filter { $0.day <= cutoff }
            let long = window(prefix, ending: cutoff, days: Configuration.longTermDays)
            let coverage = coverage(long, ending: cutoff)
            let confidence = confidence(coverage)
            guard confidence != .insufficient else { results.append(empty(cutoff, coverage)); continue }

            let longContrib = contributions(long, age: age, ending: cutoff)
            let recent = window(prefix, ending: cutoff, days: Configuration.recentDays)
            let recentContrib = contributions(recent, age: age, ending: cutoff)
            let cap = adjustmentCap(confidence, calendarDays: coverage.calendarDays)
            let rawAdjustment = clamp(totalAdjustment(longContrib), -cap, cap)
            let rawAge = clamp(age + rawAdjustment, 18, 90)
            let maturity = newEstimateWeight(confidence, calendarDays: coverage.calendarDays)
            let previous = results.last?.noopAge
            let smoothed = previous.map { $0 + maturity * (rawAge - $0) }
                ?? age + maturity * (rawAge - age)

            let paceReady = paceEligibility(days: prefix, cutoff: cutoff).isEligible
            let projectedAdjustment = clamp(totalAdjustment(recentContrib), -cap, cap)
            let projectedAge = age + 0.5 + projectedAdjustment
            let pace = paceReady ? clamp((projectedAge - smoothed) / 0.5,
                                         Configuration.minimumPace, Configuration.maximumPace) : nil
            let ageByKey = Dictionary(uniqueKeysWithValues: longContrib.map { ($0.key, $0) })
            let paceDrivers = recentContrib.map { recentItem -> NoopAgeContributor in
                let old = ageByKey[recentItem.key]?.adjustmentYears ?? 0
                return NoopAgeContributor(key: recentItem.key, label: recentItem.label, domain: recentItem.domain,
                    adjustmentYears: old, recentAdjustmentYears: recentItem.adjustmentYears - old)
            }.sorted { abs($0.recentAdjustmentYears ?? 0) > abs($1.recentAdjustmentYears ?? 0) }
            results.append(NoopAgeWeekResult(weekEndDay: cutoff, rawAge: rawAge, noopAge: smoothed,
                paceOfAging: pace, confidence: confidence, contributors: paceDrivers,
                ageContributors: longContrib, coverage: coverage, modelVersion: Configuration.modelVersion))
        }
        return results
    }

    private static func contributions(_ days: [HealthspanDay], age: Double, ending: String) -> [NoopAgeContributor] {
        var domains: [NoopAgeDomain: [(String, String, Double)]] = [:]
        func add(_ domain: NoopAgeDomain, _ key: String, _ label: String, _ lnHazard: Double?) {
            if let lnHazard, lnHazard.isFinite { domains[domain, default: []].append((key, label, lnHazard)) }
        }
        let sleep = aggregate(days, ending: ending, value: { $0.sleepMinutes })
        add(.sleep, "sleep_duration", "Sleep duration", sleep.map { max(0, abs($0 / 60 - 7.5) - 0.5) * 0.11 })
        let starts = aggregate(days, ending: ending, value: { $0.sleepStartMinute })
        let wakes = aggregate(days, ending: ending, value: { $0.wakeMinute })
        if starts != nil, wakes != nil {
            let timing = timingConsistency(days)
            add(.sleep, "sleep_consistency", "Sleep timing consistency", timing.map { (0.70 - $0) * 0.45 })
        }
        let stepTarget = age >= 60 ? 7_000.0 : 8_000.0
        add(.activity, "steps", "Daily steps", aggregate(days, ending: ending, value: { $0.steps }).map {
            clamp((stepTarget - $0) / 1_000, -3, 5) * 0.064
        })
        add(.activity, "zone_1_3", "Zones 1–3 time", aggregate(days, ending: ending, weekly: true, value: { $0.zone1to3Minutes }).map {
            clamp((100 - $0) / 100, -1.5, 1) * 0.18
        })
        add(.activity, "zone_4_5", "Zones 4–5 time", aggregate(days, ending: ending, weekly: true, value: { $0.zone4to5Minutes }).map {
            clamp((10 - $0) / 10, -1, 1) * 0.08
        })
        add(.activity, "strength", "Strength activity", aggregate(days, ending: ending, weekly: true, value: { $0.strengthMinutes }).map {
            let bounded = min($0, 120); return clamp((40 - bounded) / 40, -2, 1) * 0.12
        })
        add(.fitness, "rhr", "Resting heart rate", aggregate(days, ending: ending, value: { $0.restingHR }).map {
            clamp(($0 - 60) / 10, -2, 4) * 0.10
        })
        add(.fitness, "vo2max", "VO₂ Max", aggregate(days, ending: ending, value: { $0.vo2Max }).map {
            let expected = expectedVO2(age: age); return clamp((expected - $0) / 3.5, -4, 4) * 0.13
        })
        add(.body, "lean_mass", "Lean body mass", aggregate(days, ending: ending, value: { $0.leanMassPercent }).map {
            clamp((sexNeutralLeanTarget(age: age) - $0) / 10, 0, 2) * 0.08
        })

        var out: [NoopAgeContributor] = []
        for (domain, metrics) in domains {
            // Equal domain influence: average available submetrics before overlap shrink, so a domain with
            // more sensors cannot dominate merely because it has more rows.
            let domainScale = Configuration.domainOverlapShrink / Double(metrics.count)
            for metric in metrics {
                out.append(NoopAgeContributor(key: metric.0, label: metric.1, domain: domain,
                    adjustmentYears: metric.2 * domainScale / Configuration.lnHazardPerYear))
            }
        }
        return out.sorted { abs($0.adjustmentYears) > abs($1.adjustmentYears) }
    }

    private static func totalAdjustment(_ c: [NoopAgeContributor]) -> Double {
        guard !c.isEmpty else { return 0 }
        let domainTotals = Dictionary(grouping: c, by: \.domain).mapValues { $0.reduce(0) { $0 + $1.adjustmentYears } }
        return domainTotals.values.reduce(0, +) / Double(domainTotals.count)
    }

    private static func coverage(_ days: [HealthspanDay], ending: String) -> NoopAgeCoverage {
        guard let first = days.first else { return emptyCoverage }
        let calendar = max(1, dayDistance(first.day, ending) + 1)
        let sleep = days.filter { $0.sleepMinutes != nil && $0.sleepStartMinute != nil && $0.wakeMinute != nil }.count
        let rhr = days.filter { $0.restingHR != nil }.count
        let activity = days.filter { $0.steps != nil || $0.zone1to3Minutes != nil || $0.zone4to5Minutes != nil || $0.strengthMinutes != nil }.count
        let wear = days.filter { ($0.restingHR != nil ? 1 : 0) + ($0.sleepMinutes != nil ? 1 : 0) +
            ($0.steps != nil || $0.zone1to3Minutes != nil ? 1 : 0) >= 2 }.count
        let domains = [sleep > 0, activity > 0, rhr > 0].filter { $0 }.count
        let weeks = Set(days.filter { $0.restingHR != nil || $0.sleepMinutes != nil || $0.steps != nil }.map { weekKey($0.day) }).count
        let required = max(1, calendar * 3), present = min(required, sleep + rhr + activity)
        let known: [(String, Bool)] = [
            ("sleep_duration", days.contains { $0.sleepMinutes != nil }), ("sleep_consistency", sleep > 0),
            ("steps", days.contains { $0.steps != nil }), ("zone_1_3", days.contains { $0.zone1to3Minutes != nil }),
            ("zone_4_5", days.contains { $0.zone4to5Minutes != nil }), ("strength", days.contains { $0.strengthMinutes != nil }),
            ("rhr", rhr > 0), ("vo2max", days.contains { $0.vo2Max != nil }),
            ("lean_mass", days.contains { $0.leanMassPercent != nil })]
        return NoopAgeCoverage(calendarDays: calendar, validWearDays: wear, sleepNights: sleep, rhrDays: rhr,
            activityDays: activity, validWeeks: weeks, representedDomains: domains,
            missingProportion: 1 - Double(present) / Double(required),
            unavailableContributorKeys: known.filter { !$0.1 }.map(\.0))
    }

    private static func confidence(_ c: NoopAgeCoverage) -> NoopAgeConfidence {
        if c.calendarDays >= 180 && c.validWearDays >= 126 && c.sleepNights >= 108 && c.rhrDays >= 108 &&
            c.activityDays >= 108 && c.validWeeks >= 22 && c.representedDomains >= 3 && c.missingProportion <= 0.30 { return .established }
        if c.calendarDays >= 30 && c.validWearDays >= 21 && c.sleepNights >= 18 && c.rhrDays >= 18 &&
            c.activityDays >= 18 && c.validWeeks >= 4 && c.representedDomains >= 3 && c.missingProportion <= 0.30 { return .developing }
        if c.calendarDays >= 7 && c.validWearDays >= 7 && c.sleepNights >= 7 && c.rhrDays >= 7 &&
            c.activityDays >= 7 && c.representedDomains >= 2 && c.missingProportion <= 0.40 { return .calibrating }
        return .insufficient
    }

    public static func paceEligibility(days: [HealthspanDay], cutoff: String) -> PaceEligibility {
        let prefix = days.filter { $0.day <= cutoff }
        let recentStart = addingDays(cutoff, -(Configuration.recentDays - 1))
        let recent = prefix.filter { $0.day >= recentStart }
        let older = prefix.filter { $0.day < recentStart }
        let recentWear = recent.filter(isWearDay)
        let olderWear = older.filter(isWearDay)
        let validWear = prefix.filter(isWearDay)
        let recentC = coverage(recent, ending: cutoff)
        let olderDomains = [older.contains { $0.sleepMinutes != nil }, older.contains { $0.restingHR != nil },
                            older.contains { $0.steps != nil || $0.zone1to3Minutes != nil }].filter { $0 }.count
        return PaceEligibility(recentWearDays: recentWear.count, olderWearDays: olderWear.count,
            validWeeks: Set(validWear.map { weekKey($0.day) }).count,
            recentDomains: recentC.representedDomains, olderDomains: olderDomains)
    }

    private static func isWearDay(_ day: HealthspanDay) -> Bool {
        (day.restingHR != nil ? 1 : 0) + (day.sleepMinutes != nil ? 1 : 0) +
        (day.steps != nil || day.zone1to3Minutes != nil ? 1 : 0) >= 2
    }

    private static func aggregate(_ days: [HealthspanDay], ending: String, weekly: Bool = false,
                                  value: (HealthspanDay) -> Double?) -> Double? {
        let points = days.compactMap { d -> (Double, Double)? in
            guard let v = value(d), v.isFinite else { return nil }
            let age = Double(max(0, dayDistance(d.day, ending)))
            return (v, pow(0.5, age / Configuration.recencyHalfLifeDays))
        }
        guard !points.isEmpty else { return nil }
        let sorted = points.map(\.0).sorted(), lo = sorted[Int(Double(sorted.count - 1) * 0.05)]
        let hi = sorted[Int(Double(sorted.count - 1) * 0.95)]
        let weighted = points.reduce((sum: 0.0, weight: 0.0)) { acc, p in
            (acc.sum + clamp(p.0, lo, hi) * p.1, acc.weight + p.1)
        }
        let daily = weighted.sum / weighted.weight
        return weekly ? daily * 7 : daily
    }

    private static func timingConsistency(_ days: [HealthspanDay]) -> Double? {
        let starts = days.compactMap(\.sleepStartMinute), wakes = days.compactMap(\.wakeMinute)
        guard starts.count >= 3, wakes.count >= 3 else { return nil }
        func circularSD(_ xs: [Double]) -> Double {
            let angles = xs.map { $0 / 1440 * 2 * Double.pi }
            let r = hypot(angles.map(cos).reduce(0,+), angles.map(sin).reduce(0,+)) / Double(angles.count)
            return sqrt(max(0, -2 * log(max(r, 0.0001)))) * 1440 / (2 * Double.pi)
        }
        return clamp(1 - (circularSD(starts) + circularSD(wakes)) / 360, 0, 1)
    }

    private static func adjustmentCap(_ c: NoopAgeConfidence, calendarDays: Int) -> Double {
        switch c { case .calibrating: return 3; case .developing: return calendarDays < 60 ? 5 : 7.5
        case .established: return 10; case .insufficient: return 0 }
    }
    private static func newEstimateWeight(_ c: NoopAgeConfidence, calendarDays: Int) -> Double {
        switch c { case .calibrating: return 0.20; case .developing: return calendarDays < 60 ? 0.30 : 0.40
        case .established: return 0.50; case .insufficient: return 0 }
    }
    private static func expectedVO2(age: Double) -> Double { clamp(52 - 0.30 * (age - 20), 24, 52) }
    private static func sexNeutralLeanTarget(age: Double) -> Double { age >= 65 ? 65 : 70 }
    private static func window(_ days: [HealthspanDay], ending: String, days count: Int) -> [HealthspanDay] {
        let start = addingDays(ending, -(count - 1)); return days.filter { $0.day >= start && $0.day <= ending }
    }
    private static let emptyCoverage = NoopAgeCoverage(calendarDays: 0, validWearDays: 0, sleepNights: 0,
        rhrDays: 0, activityDays: 0, validWeeks: 0, representedDomains: 0, missingProportion: 1,
        unavailableContributorKeys: [])
    private static func empty(_ day: String, _ coverage: NoopAgeCoverage = emptyCoverage) -> NoopAgeWeekResult {
        NoopAgeWeekResult(weekEndDay: day, rawAge: nil, noopAge: nil, paceOfAging: nil,
            confidence: .insufficient, contributors: [], ageContributors: [], coverage: coverage,
            modelVersion: Configuration.modelVersion)
    }
    private static func dayDistance(_ a: String, _ b: String) -> Int {
        guard let x = formatter.date(from: a), let y = formatter.date(from: b) else { return 0 }
        return Int((y.timeIntervalSince(x) / 86_400).rounded())
    }
    private static func addingDays(_ day: String, _ n: Int) -> String {
        guard let d = formatter.date(from: day) else { return day }
        return formatter.string(from: Calendar.utc.date(byAdding: .day, value: n, to: d) ?? d)
    }
    private static func weekKey(_ day: String) -> String {
        guard let d = formatter.date(from: day) else { return day }
        let weekday = Calendar.utc.component(.weekday, from: d), add = (7 - weekday) % 7
        return formatter.string(from: Calendar.utc.date(byAdding: .day, value: add, to: d) ?? d)
    }
    private static let formatter: DateFormatter = { let f = DateFormatter(); f.calendar = Calendar.utc
        f.locale = Locale(identifier: "en_US_POSIX"); f.timeZone = TimeZone(secondsFromGMT: 0); f.dateFormat = "yyyy-MM-dd"; return f }()
    private static func clamp(_ x: Double, _ lo: Double, _ hi: Double) -> Double { min(hi, max(lo, x)) }
}

private extension Calendar {
    static var utc: Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(secondsFromGMT: 0)!; return c }
}
