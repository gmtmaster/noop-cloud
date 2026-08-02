import Foundation

/// One canonical night's inputs for NOOP's local sleep-planning model.
/// Inputs must be chronological. Imported WHOOP figures are references only.
public struct SleepPlanningNightInput: Equatable, Sendable {
    public let day: String
    public let mainSleepMinutes: Double?
    public let napSleepMinutes: Double
    public let strain: Double?
    public let efficiency: Double?
    public let importedWhoopNeedMinutes: Double?
    public let importedWhoopDebtMinutes: Double?

    public init(day: String, mainSleepMinutes: Double?, napSleepMinutes: Double = 0,
                strain: Double? = nil, efficiency: Double? = nil,
                importedWhoopNeedMinutes: Double? = nil, importedWhoopDebtMinutes: Double? = nil) {
        self.day = day
        self.mainSleepMinutes = mainSleepMinutes
        self.napSleepMinutes = napSleepMinutes
        self.strain = strain
        self.efficiency = efficiency
        self.importedWhoopNeedMinutes = importedWhoopNeedMinutes
        self.importedWhoopDebtMinutes = importedWhoopDebtMinutes
    }
}

public struct SleepPlanningBreakdown: Equatable, Sendable {
    public let baselineMinutes: Double
    public let recentDebtMinutes: Double
    public let debtRecoveryMinutes: Double
    public let strainAdjustmentMinutes: Double
    public let napCreditMinutes: Double
    public let sleepNeedMinutes: Double
    public let expectedEfficiency: Double
    public let timeInBedMinutes: Double
    public let confidence: SleepNeedConfidence

    // Presentation aliases retained while the screens move to the planning vocabulary.
    public var debtAdjustmentMinutes: Double { debtRecoveryMinutes }
    public var totalSleepNeedMinutes: Double { sleepNeedMinutes }
    public var recommendedTimeInBedMinutes: Double? { timeInBedMinutes }
}

public struct SleepPlanningHistoryPoint: Equatable, Sendable {
    public let day: String
    public let planBeforeNight: SleepPlanningBreakdown
    public let actualMainSleepMinutes: Double?
    public let baseRequirementMinutes: Double
    public let deficitMinutes: Double?
    public let surplusRepaymentMinutes: Double?
    /// Signed raw change before recency weighting: positive adds debt, negative repays it.
    public let rawDebtChangeMinutes: Double?
    public let recentDebtMinutes: Double?
    public let importedWhoopNeedMinutes: Double?
    public let importedWhoopDebtMinutes: Double?
}

public struct SleepPlanningResult: Equatable, Sendable {
    public let history: [SleepPlanningHistoryPoint]
    public let tonight: SleepPlanningBreakdown
    public let recentContributions: [SleepPlanningDebtContribution]
}

public struct SleepPlanningDebtContribution: Equatable, Sendable {
    public let day: String
    public let rawDebtChangeMinutes: Double
    public let weightedDebtChangeMinutes: Double
}

/// NOOP's transparent, bounded, WHOOP-inspired local sleep planner.
/// It is not a reproduction of WHOOP's proprietary formula.
public enum SleepPlanningEngine {
    public static let modelVersion = 3

    public enum Configuration {
        public static let debtWindowNights = 14
        public static let onTargetDisplayBandMinutes = 30.0
        /// Each step into the past multiplies a nightly contribution by this factor.
        public static let debtDecayPerNight = 0.90
        public static let surplusRepaymentFraction = 0.75

        public static let fallbackBaselineMinutes = 450.0
        public static let minimumBaselineMinutes = 450.0
        public static let maximumBaselineMinutes = 540.0
        public static let baselineHistoryNights = 28
        /// Enough valid sleeps to establish the baseline for every contribution in the 14-sleep debt window.
        public static let maximumInputHistoryNights = baselineHistoryNights + debtWindowNights
        public static let minimumPersonalizationNights = 7
        public static let establishedHistoryNights = 21
        public static let baselinePercentile = 0.70

        /// Effort is NOOP's native 0...100 scale. A quadratic curve keeps low Effort negligible.
        public static let maximumStrain = 100.0
        public static let maximumStrainAdjustmentMinutes = 30.0

        public static let napCreditFraction = 0.80
        public static let maximumNapCreditMinutes = 120.0
        public static let minimumSleepNeedMinutes = 360.0

        public static let debtRecoveryFraction = 0.25
        public static let maximumNightlyDebtRecoveryMinutes = 60.0

        public static let efficiencyHistoryNights = 14
        public static let minimumEfficiencySamples = 7
        public static let fallbackEfficiency = 0.90
        public static let minimumExpectedEfficiency = 0.75
        public static let maximumExpectedEfficiency = 0.98
    }

    private struct Contribution {
        let day: String
        let raw: Double
    }

    public static func evaluate(_ inputs: [SleepPlanningNightInput],
                                tonightStrain: Double? = nil,
                                tonightNapSleepMinutes: Double = 0) -> SleepPlanningResult {
        var priorSleeps: [Double] = []
        var priorEfficiencies: [Double] = []
        var contributions: [Contribution] = []
        var history: [SleepPlanningHistoryPoint] = []

        for input in boundedInputs(inputs) {
            let debtBefore = weightedDebt(contributions)
            let plan = breakdown(priorSleeps: priorSleeps, priorEfficiencies: priorEfficiencies,
                                 recentDebt: debtBefore, strain: input.strain,
                                 napSleepMinutes: input.napSleepMinutes)
            let baseRequirement = max(Configuration.minimumSleepNeedMinutes,
                                      plan.baselineMinutes + plan.strainAdjustmentMinutes - plan.napCreditMinutes)
            guard let actual = validPositive(input.mainSleepMinutes) else {
                history.append(SleepPlanningHistoryPoint(
                    day: input.day, planBeforeNight: plan, actualMainSleepMinutes: nil,
                    baseRequirementMinutes: round1(baseRequirement), deficitMinutes: nil,
                    surplusRepaymentMinutes: nil, rawDebtChangeMinutes: nil,
                    recentDebtMinutes: nil,
                    importedWhoopNeedMinutes: input.importedWhoopNeedMinutes,
                    importedWhoopDebtMinutes: input.importedWhoopDebtMinutes))
                continue
            }

            let deficit = max(0, baseRequirement - actual)
            let repayment = max(0, actual - baseRequirement) * Configuration.surplusRepaymentFraction
            let rawChange = deficit - repayment
            contributions.append(Contribution(day: input.day, raw: rawChange))
            if contributions.count > Configuration.debtWindowNights {
                contributions.removeFirst(contributions.count - Configuration.debtWindowNights)
            }
            let debtAfter = weightedDebt(contributions)
            history.append(SleepPlanningHistoryPoint(
                day: input.day, planBeforeNight: plan, actualMainSleepMinutes: round1(actual),
                baseRequirementMinutes: round1(baseRequirement), deficitMinutes: round1(deficit),
                surplusRepaymentMinutes: round1(repayment), rawDebtChangeMinutes: round1(rawChange),
                recentDebtMinutes: round1(debtAfter),
                importedWhoopNeedMinutes: input.importedWhoopNeedMinutes,
                importedWhoopDebtMinutes: input.importedWhoopDebtMinutes))
            priorSleeps.append(actual)
            if let efficiency = normalizedEfficiency(input.efficiency) { priorEfficiencies.append(efficiency) }
        }

        let tonight = breakdown(priorSleeps: priorSleeps, priorEfficiencies: priorEfficiencies,
                                recentDebt: weightedDebt(contributions), strain: tonightStrain,
                                napSleepMinutes: tonightNapSleepMinutes)
        let count = contributions.count
        let recentContributions = contributions.enumerated().map { index, contribution in
            let age = count - 1 - index
            return SleepPlanningDebtContribution(day: contribution.day,
                rawDebtChangeMinutes: round1(contribution.raw),
                weightedDebtChangeMinutes: round1(contribution.raw * pow(Configuration.debtDecayPerNight, Double(age))))
        }
        return SleepPlanningResult(history: history, tonight: tonight,
                                   recentContributions: recentContributions)
    }

    public static func recommendedBedtime(plannedWake: Date, timeInBedMinutes: Double) -> Date {
        plannedWake.addingTimeInterval(-max(0, timeInBedMinutes) * 60)
    }

    public static func strainAdjustment(for strain: Double?) -> Double {
        guard let strain, strain.isFinite, strain > 0 else { return 0 }
        let normalized = min(strain, Configuration.maximumStrain) / Configuration.maximumStrain
        return normalized * normalized * Configuration.maximumStrainAdjustmentMinutes
    }

    private static func breakdown(priorSleeps: [Double], priorEfficiencies: [Double],
                                  recentDebt: Double, strain: Double?, napSleepMinutes: Double) -> SleepPlanningBreakdown {
        let sleeps = Array(priorSleeps.suffix(Configuration.baselineHistoryNights))
        let confidence: SleepNeedConfidence
        let baseline: Double
        if sleeps.count < Configuration.minimumPersonalizationNights {
            confidence = .fallback
            baseline = Configuration.fallbackBaselineMinutes
        } else {
            confidence = sleeps.count >= Configuration.establishedHistoryNights ? .established : .limited
            baseline = clamp(percentile(sleeps, p: Configuration.baselinePercentile),
                             Configuration.minimumBaselineMinutes, Configuration.maximumBaselineMinutes)
        }
        let strainMinutes = strainAdjustment(for: strain)
        let napCredit = min(max(0, napSleepMinutes) * Configuration.napCreditFraction,
                            Configuration.maximumNapCreditMinutes)
        let debtRecovery = min(max(0, recentDebt) * Configuration.debtRecoveryFraction,
                               Configuration.maximumNightlyDebtRecoveryMinutes)
        let need = max(Configuration.minimumSleepNeedMinutes,
                       baseline + strainMinutes - napCredit + debtRecovery)
        let validEfficiencies = priorEfficiencies.compactMap(normalizedEfficiency)
        let efficiency = validEfficiencies.count >= Configuration.minimumEfficiencySamples
            ? clamp(percentile(Array(validEfficiencies.suffix(Configuration.efficiencyHistoryNights)), p: 0.50),
                    Configuration.minimumExpectedEfficiency, Configuration.maximumExpectedEfficiency)
            : Configuration.fallbackEfficiency
        return SleepPlanningBreakdown(
            baselineMinutes: round1(baseline), recentDebtMinutes: round1(recentDebt),
            debtRecoveryMinutes: round1(debtRecovery), strainAdjustmentMinutes: round1(strainMinutes),
            napCreditMinutes: round1(napCredit), sleepNeedMinutes: round1(need),
            expectedEfficiency: round3(efficiency), timeInBedMinutes: round1(need / efficiency),
            confidence: confidence)
    }

    private static func weightedDebt(_ contributions: [Contribution]) -> Double {
        let recent = contributions.suffix(Configuration.debtWindowNights)
        let count = recent.count
        let net = recent.enumerated().reduce(0.0) { total, pair in
            let age = count - 1 - pair.offset
            return total + pair.element.raw * pow(Configuration.debtDecayPerNight, Double(age))
        }
        return max(0, net)
    }

    private static func boundedInputs(_ inputs: [SleepPlanningNightInput]) -> ArraySlice<SleepPlanningNightInput> {
        var validSeen = 0
        var start = inputs.startIndex
        for index in inputs.indices.reversed() {
            if validPositive(inputs[index].mainSleepMinutes) != nil { validSeen += 1 }
            start = index
            if validSeen >= Configuration.maximumInputHistoryNights { break }
        }
        return inputs[start...]
    }

    private static func validPositive(_ value: Double?) -> Double? {
        guard let value, value.isFinite, value > 0 else { return nil }
        return value
    }
    private static func normalizedEfficiency(_ value: Double?) -> Double? {
        guard let value, value.isFinite, value > 0 else { return nil }
        let normalized = value > 1 ? value / 100 : value
        return normalized > 0 && normalized <= 1 ? normalized : nil
    }
    private static func percentile(_ values: [Double], p: Double) -> Double {
        let sorted = values.sorted()
        guard sorted.count > 1 else { return sorted.first ?? 0 }
        let position = clamp(p, 0, 1) * Double(sorted.count - 1)
        let lower = Int(position.rounded(.down)), upper = Int(position.rounded(.up))
        if lower == upper { return sorted[lower] }
        return sorted[lower] + (sorted[upper] - sorted[lower]) * (position - Double(lower))
    }
    private static func clamp(_ value: Double, _ lower: Double, _ upper: Double) -> Double {
        min(max(value, lower), upper)
    }
    private static func round1(_ value: Double) -> Double { (value * 10).rounded() / 10 }
    private static func round3(_ value: Double) -> Double { (value * 1_000).rounded() / 1_000 }
}
