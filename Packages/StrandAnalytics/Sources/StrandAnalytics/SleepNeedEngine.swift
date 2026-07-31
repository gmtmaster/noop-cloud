import Foundation

/// Confidence in NOOP's locally-derived Sleep Need. This never describes an imported WHOOP value.
public enum SleepNeedConfidence: String, Equatable, Sendable {
    case fallback
    case limited
    case established
}

/// Transparent components of NOOP Sleep Need for one sleep cycle.
public struct SleepNeedBreakdown: Equatable, Sendable {
    public let baselineMinutes: Double
    public let debtAdjustmentMinutes: Double
    public let strainAdjustmentMinutes: Double
    public let napCreditMinutes: Double
    public let totalSleepNeedMinutes: Double
    public let expectedEfficiency: Double?
    public let recommendedTimeInBedMinutes: Double?
    public let confidence: SleepNeedConfidence
}

/// Canonical inputs for one local sleep cycle. `mainSleepMinutes` excludes naps; naps are supplied
/// separately so they can credit need without being counted twice as the night's main sleep.
public struct SleepNeedNightInput: Equatable, Sendable {
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

/// One point in the deterministic, chronological NOOP debt series. A missing main sleep produces a
/// point with `carriedDebtMinutes == nil`; the previous balance is retained for the next real night.
public struct SleepDebtHistoryPoint: Equatable, Sendable {
    public let day: String
    public let breakdown: SleepNeedBreakdown
    public let actualMainSleepMinutes: Double?
    public let nightlyDeficitMinutes: Double?
    public let repaymentMinutes: Double?
    public let carriedDebtMinutes: Double?
    public let importedWhoopNeedMinutes: Double?
    public let importedWhoopDebtMinutes: Double?
}

/// NOOP's versioned, presentation-only Sleep Need and carried-debt model.
public enum SleepNeedEngine {
    public static let modelVersion = 2

    public enum Configuration {
        public static let fallbackBaselineMinutes = 450.0
        public static let minimumBaselineMinutes = 450.0
        public static let maximumBaselineMinutes = 540.0
        public static let limitedHistoryNights = 7
        public static let establishedHistoryNights = 21
        public static let historyWindowNights = 28
        public static let baselinePercentile = 0.70

        /// Product policy: surplus sleep repays 75% of its minutes so a single long night does not
        /// unrealistically erase an accumulated balance. This is a NOOP choice, not a WHOOP formula.
        public static let surplusRepaymentFraction = 0.75
        /// Product policy: offer half of raw carried debt as tonight's gradual repayment contribution.
        /// This is a NOOP choice inherited from the original local model, not a WHOOP formula.
        public static let rawDebtContributionFraction = 0.50
        /// Product policy: never add more than two hours of debt repayment to one night's Sleep Need.
        /// This caps only the recommendation contribution; it never caps or overwrites raw debt.
        public static let maximumNightlyDebtContributionMinutes = 120.0

        /// Internal Strain/Effort is 0...100. The adjustment is zero through 50, then rises linearly
        /// to 30 minutes at 100 and remains capped there.
        public static let strainAdjustmentThreshold = 50.0
        public static let maximumStrain = 100.0
        public static let maximumStrainAdjustmentMinutes = 30.0

        public static let napCreditFraction = 0.80
        public static let maximumNapCreditMinutes = 120.0
        public static let minimumTotalNeedMinutes = 360.0

        public static let minimumEfficiency = 0.75
        public static let maximumEfficiency = 0.98
        public static let minimumEfficiencyNights = 7
    }

    /// Builds one result using prior main sleeps only. History must be chronological and must not include
    /// the target night's main sleep; callers calculating history get this guarantee from `history(_:)`.
    public static func calculate(priorMainSleepMinutes: [Double], priorEfficiencies: [Double],
                                 carriedDebtMinutes: Double, strain: Double?,
                                 qualifyingNapSleepMinutes: Double) -> SleepNeedBreakdown {
        let validSleeps = Array(priorMainSleepMinutes.filter { $0.isFinite && $0 > 0 }
            .suffix(Configuration.historyWindowNights))
        let confidence: SleepNeedConfidence
        let baseline: Double
        if validSleeps.count < Configuration.limitedHistoryNights {
            confidence = .fallback
            baseline = Configuration.fallbackBaselineMinutes
        } else {
            confidence = validSleeps.count >= Configuration.establishedHistoryNights ? .established : .limited
            baseline = clamp(percentile(validSleeps, p: Configuration.baselinePercentile),
                             Configuration.minimumBaselineMinutes, Configuration.maximumBaselineMinutes)
        }

        let debtAdjustment = min(
            max(0, carriedDebtMinutes) * Configuration.rawDebtContributionFraction,
            Configuration.maximumNightlyDebtContributionMinutes)
        let strainAdjustment = self.strainAdjustment(for: strain)
        let napCredit = min(max(0, qualifyingNapSleepMinutes) * Configuration.napCreditFraction,
                            Configuration.maximumNapCreditMinutes)
        let total = max(Configuration.minimumTotalNeedMinutes,
                        baseline + debtAdjustment + strainAdjustment - napCredit)

        let efficiencies = Array(priorEfficiencies.compactMap(normalizedEfficiency)
            .suffix(Configuration.historyWindowNights))
        let expected = efficiencies.count >= Configuration.minimumEfficiencyNights
            ? clamp(percentile(efficiencies, p: 0.50), Configuration.minimumEfficiency,
                    Configuration.maximumEfficiency)
            : nil

        return SleepNeedBreakdown(
            baselineMinutes: round1(baseline), debtAdjustmentMinutes: round1(debtAdjustment),
            strainAdjustmentMinutes: round1(strainAdjustment), napCreditMinutes: round1(napCredit),
            totalSleepNeedMinutes: round1(total), expectedEfficiency: expected.map(round3),
            recommendedTimeInBedMinutes: expected.map { round1(total / $0) }, confidence: confidence)
    }

    /// Produces a no-look-ahead series. Imported WHOOP values travel alongside the local model as
    /// untouched references and never enter NOOP's baseline or debt calculation.
    public static func history(_ inputs: [SleepNeedNightInput]) -> [SleepDebtHistoryPoint] {
        var priorSleeps: [Double] = []
        var priorEfficiencies: [Double] = []
        var carriedDebt = 0.0
        return inputs.map { input in
            let breakdown = calculate(priorMainSleepMinutes: priorSleeps,
                                      priorEfficiencies: priorEfficiencies,
                                      carriedDebtMinutes: carriedDebt, strain: input.strain,
                                      qualifyingNapSleepMinutes: input.napSleepMinutes)
            guard let actual = input.mainSleepMinutes, actual.isFinite, actual > 0 else {
                return SleepDebtHistoryPoint(day: input.day, breakdown: breakdown,
                    actualMainSleepMinutes: nil, nightlyDeficitMinutes: nil, repaymentMinutes: nil,
                    carriedDebtMinutes: nil, importedWhoopNeedMinutes: input.importedWhoopNeedMinutes,
                    importedWhoopDebtMinutes: input.importedWhoopDebtMinutes)
            }
            // Debt is measured against tonight's requirement before any prior-debt adjustment.
            // Feeding the adjustment back into the ledger makes old debt manufacture new debt and
            // prevents baseline sleep from stabilizing the balance. The 120-minute cap belongs only
            // to the recommendation contribution; it must never cap or overwrite the raw balance.
            let requirementExcludingDebt = max(
                Configuration.minimumTotalNeedMinutes,
                breakdown.baselineMinutes + breakdown.strainAdjustmentMinutes - breakdown.napCreditMinutes)
            let deficit = max(0, requirementExcludingDebt - actual)
            let surplus = max(0, actual - requirementExcludingDebt)
            let repayment = surplus * Configuration.surplusRepaymentFraction
            carriedDebt = max(0, carriedDebt + deficit - repayment)
            priorSleeps.append(actual)
            if let efficiency = normalizedEfficiency(input.efficiency) { priorEfficiencies.append(efficiency) }
            return SleepDebtHistoryPoint(day: input.day, breakdown: breakdown,
                actualMainSleepMinutes: round1(actual), nightlyDeficitMinutes: round1(deficit),
                repaymentMinutes: round1(repayment), carriedDebtMinutes: round1(carriedDebt),
                importedWhoopNeedMinutes: input.importedWhoopNeedMinutes,
                importedWhoopDebtMinutes: input.importedWhoopDebtMinutes)
        }
    }

    public static func strainAdjustment(for strain: Double?) -> Double {
        guard let strain, strain.isFinite, strain > Configuration.strainAdjustmentThreshold else { return 0 }
        let fraction = (min(strain, Configuration.maximumStrain) - Configuration.strainAdjustmentThreshold)
            / (Configuration.maximumStrain - Configuration.strainAdjustmentThreshold)
        return fraction * Configuration.maximumStrainAdjustmentMinutes
    }

    private static func normalizedEfficiency(_ value: Double?) -> Double? {
        guard let value, value.isFinite, value > 0 else { return nil }
        let normalized = value > 1 ? value / 100 : value
        guard normalized > 0, normalized <= 1 else { return nil }
        return normalized
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
