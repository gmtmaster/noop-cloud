import Foundation

public enum NoopAgeConfidence: String, Equatable, Sendable {
    case insufficient, developing, established
}

public enum NoopAgeImpact: String, Equatable, Sendable {
    case helping, holdingBack
}

public struct NoopAgeContributor: Equatable, Sendable {
    public let key: String
    public let label: String
    public let adjustmentYears: Double
    public var impact: NoopAgeImpact { adjustmentYears <= 0 ? .helping : .holdingBack }
}

public struct NoopAgeWeekInput: Equatable, Sendable {
    public let weekEndDay: String
    public let chronologicalAge: Double?
    public let sex: String
    public let restingHR: [Double]
    public let strain: [Double]
    public let hrv: [Double]
    public let sleepMinutes: [Double]
    public let recentSleepDebtMinutes: Double?
    public let recovery: [Double]
    public let workoutCount: Int

    public init(weekEndDay: String, chronologicalAge: Double?, sex: String,
                restingHR: [Double], strain: [Double], hrv: [Double],
                sleepMinutes: [Double], recentSleepDebtMinutes: Double?,
                recovery: [Double], workoutCount: Int) {
        self.weekEndDay = weekEndDay; self.chronologicalAge = chronologicalAge; self.sex = sex
        self.restingHR = restingHR; self.strain = strain; self.hrv = hrv
        self.sleepMinutes = sleepMinutes; self.recentSleepDebtMinutes = recentSleepDebtMinutes
        self.recovery = recovery; self.workoutCount = workoutCount
    }
}

public struct NoopAgeWeekResult: Equatable, Sendable {
    public let weekEndDay: String
    public let rawAge: Double?
    public let noopAge: Double?
    public let paceOfAging: Double?
    public let confidence: NoopAgeConfidence
    public let contributors: [NoopAgeContributor]
}

/// A transparent weekly functional-fitness trajectory. This is not biological age or disease risk.
public enum NoopAgeEngine {
    public enum Configuration {
        public static let minimumRHRNights = 4
        public static let establishedWeeks = 4
        public static let smoothingWeeks = 3
        public static let paceMinimumWeeks = 4
        public static let paceWindowWeeks = 8
        public static let minimumPace = 0.7
        public static let maximumPace = 1.3
        public static let paceSlopeScale = 0.25
        public static let maximumTotalAdjustmentYears = 10.0
        public static let maximumFitnessAdjustmentYears = 8.0
        public static let maximumHRVAdjustmentYears = 1.0
        public static let maximumSleepConsistencyAdjustmentYears = 1.0
        public static let maximumSleepPerformanceAdjustmentYears = 0.75
        public static let maximumDebtAdjustmentYears = 1.25
        public static let maximumRecoveryAdjustmentYears = 0.75
        public static let maximumWorkoutAdjustmentYears = 1.0
    }

    public static func evaluate(_ inputs: [NoopAgeWeekInput]) -> [NoopAgeWeekResult] {
        let weeks = inputs.sorted { $0.weekEndDay < $1.weekEndDay }
        var raw: [Double?] = []
        var output: [NoopAgeWeekResult] = []
        for (index, week) in weeks.enumerated() {
            let computed = computeRaw(week, priorWeeks: Array(weeks[..<index]))
            raw.append(computed.age)
            let smoothed = smooth(raw)
            let validWeeks = raw.compactMap { $0 }.count
            let confidence: NoopAgeConfidence
            if computed.age == nil { confidence = .insufficient }
            else if validWeeks >= Configuration.establishedWeeks && computed.availableFactors >= 5 {
                confidence = .established
            } else { confidence = .developing }
            let provisional = NoopAgeWeekResult(
                weekEndDay: week.weekEndDay, rawAge: rounded(computed.age), noopAge: rounded(smoothed),
                paceOfAging: nil, confidence: confidence, contributors: computed.contributors)
            output.append(provisional)
            let pace = paceForPrefix(output)
            output[index] = NoopAgeWeekResult(
                weekEndDay: provisional.weekEndDay, rawAge: provisional.rawAge,
                noopAge: provisional.noopAge, paceOfAging: rounded(pace),
                confidence: provisional.confidence, contributors: provisional.contributors)
        }
        return output
    }

    private static func computeRaw(_ week: NoopAgeWeekInput, priorWeeks: [NoopAgeWeekInput])
        -> (age: Double?, contributors: [NoopAgeContributor], availableFactors: Int) {
        guard let chrono = week.chronologicalAge, chrono > 0,
              week.restingHR.count >= Configuration.minimumRHRNights else { return (nil, [], 0) }
        let rhr = median(week.restingHR)
        let active = week.strain.filter { $0 >= 30 }
        let pa = FitnessAgeEngine.physicalActivityIndexFromStrain(
            activeDaysPerWeek: active.count, meanActiveStrain: mean(active) ?? 0)
        let fitness = FitnessAgeEngine.fitnessAge(age: chrono, sex: week.sex, restingHR: rhr, paIndex: pa)
        var factors = 1
        var contributors = [contributor("fitness", "Cardio fitness & resting HR",
            clamp(fitness - chrono, -Configuration.maximumFitnessAdjustmentYears,
                  Configuration.maximumFitnessAdjustmentYears))]

        if week.hrv.count >= 3 {
            let prior = priorWeeks.suffix(4).flatMap(\.hrv)
            let delta = prior.count >= 6 ? (median(week.hrv) / max(median(prior), 1) - 1) : 0
            contributors.append(contributor("hrv", "HRV trend",
                clamp(-delta * 5, -Configuration.maximumHRVAdjustmentYears,
                      Configuration.maximumHRVAdjustmentYears))); factors += 1
        }
        if week.sleepMinutes.count >= 4 {
            let sd = standardDeviation(week.sleepMinutes)
            contributors.append(contributor("sleep_consistency", "Sleep consistency",
                clamp((sd - 60) / 60, -Configuration.maximumSleepConsistencyAdjustmentYears,
                      Configuration.maximumSleepConsistencyAdjustmentYears)))
            let avg = mean(week.sleepMinutes) ?? 480
            contributors.append(contributor("sleep_performance", "Sleep duration",
                clamp((450 - avg) / 120, -Configuration.maximumSleepPerformanceAdjustmentYears,
                      Configuration.maximumSleepPerformanceAdjustmentYears))); factors += 2
        }
        if let debt = week.recentSleepDebtMinutes {
            contributors.append(contributor("sleep_debt", "Recent Sleep Debt",
                clamp(debt / 240, 0, Configuration.maximumDebtAdjustmentYears))); factors += 1
        }
        if week.recovery.count >= 4 {
            contributors.append(contributor("recovery", "Recovery consistency",
                clamp((standardDeviation(week.recovery) - 15) / 30,
                      -Configuration.maximumRecoveryAdjustmentYears,
                      Configuration.maximumRecoveryAdjustmentYears))); factors += 1
        }
        contributors.append(contributor("workouts", "Workout regularity",
            clamp(Double(3 - week.workoutCount) / 3,
                  -Configuration.maximumWorkoutAdjustmentYears,
                  Configuration.maximumWorkoutAdjustmentYears))); factors += 1

        let total = clamp(contributors.reduce(0) { $0 + $1.adjustmentYears },
                          -Configuration.maximumTotalAdjustmentYears,
                          Configuration.maximumTotalAdjustmentYears)
        let age = clamp(chrono + total, FitnessAgeEngine.minAge, FitnessAgeEngine.maxAge)
        return (age, contributors.sorted { abs($0.adjustmentYears) > abs($1.adjustmentYears) }, factors)
    }

    private static func smooth(_ raw: [Double?]) -> Double? {
        let values = raw.suffix(Configuration.smoothingWeeks).compactMap { $0 }
        guard let last = values.last else { return nil }
        guard values.count > 1 else { return last }
        let weights = Array(1...values.count).map(Double.init)
        return zip(values, weights).reduce(0) { $0 + $1.0 * $1.1 } / weights.reduce(0, +)
    }

    private static func paceForPrefix(_ results: [NoopAgeWeekResult]) -> Double? {
        let values = results.suffix(Configuration.paceWindowWeeks).compactMap(\.noopAge)
        guard values.count >= Configuration.paceMinimumWeeks else { return nil }
        let n = Double(values.count), xs = (0..<values.count).map(Double.init)
        let xMean = (n - 1) / 2, yMean = values.reduce(0, +) / n
        let numerator = zip(xs, values).reduce(0) { $0 + ($1.0 - xMean) * ($1.1 - yMean) }
        let denominator = xs.reduce(0) { $0 + pow($1 - xMean, 2) }
        let slope = denominator > 0 ? numerator / denominator : 0
        return clamp(1 + slope / Configuration.paceSlopeScale,
                     Configuration.minimumPace, Configuration.maximumPace)
    }

    private static func contributor(_ key: String, _ label: String, _ adjustment: Double) -> NoopAgeContributor {
        NoopAgeContributor(key: key, label: label, adjustmentYears: rounded(adjustment) ?? 0)
    }
    private static func mean(_ x: [Double]) -> Double? { x.isEmpty ? nil : x.reduce(0, +) / Double(x.count) }
    private static func median(_ x: [Double]) -> Double {
        let s = x.sorted(); guard !s.isEmpty else { return 0 }
        return s.count.isMultiple(of: 2) ? (s[s.count / 2 - 1] + s[s.count / 2]) / 2 : s[s.count / 2]
    }
    private static func standardDeviation(_ x: [Double]) -> Double {
        guard let m = mean(x), x.count > 1 else { return 0 }
        return sqrt(x.reduce(0) { $0 + pow($1 - m, 2) } / Double(x.count))
    }
    private static func clamp(_ value: Double, _ low: Double, _ high: Double) -> Double { min(high, max(low, value)) }
    private static func rounded(_ value: Double?) -> Double? { value.map { ($0 * 10).rounded() / 10 } }
}
