import Foundation

// MARK: - Marker dictionary (non-diagnostic)
//
// MarkerCatalog.swift — a small dictionary of common, NON-DIAGNOSTIC marker
// definitions so the user can pick a marker by name (with a sensible canonical unit
// and decimal precision prefilled) instead of typing everything free-hand.
//
// Per the Health Records design spec (2026-06-19-v5-health-records-design.md,
// §"New" and §"Non-clinical / legal framing"):
//   - This ships NO reference-range tables. `referenceTextHint` is a neutral
//     placeholder prompting the user to copy the range FROM THEIR OWN REPORT — NOOP
//     never defines, computes, or asserts a normal range.
//   - `higherIsBetter` is intentionally `nil` for every entry: NOOP makes no value
//     judgement about a marker's direction. The field exists only so a future
//     descriptive sparkline could phrase a trend, never a clinical verdict.
//   - The catalog is NOT a gate: a user can always add a custom marker (free name +
//     unit), so the store is never limited by this dictionary.
//
// Pure data — no DB, no I/O. Mirrors the flat, deterministic style of the other
// StrandImport model files.

/// A non-diagnostic marker definition: how to label and format one marker the user
/// chooses from the picker. Carries NO clinical thresholds.
public struct MarkerDefinition: Sendable, Equatable, Codable {
    /// Stable key stored on every `LabMarker` (e.g. `"ldl"`, `"bp_systolic"`).
    public let key: String
    /// Human display name (e.g. `"LDL cholesterol"`).
    public let displayName: String
    /// Organisational category for grouping in the Lab Book.
    public let category: LabMarkerCategory
    /// Canonical unit prefilled in the editor (e.g. `"mmol/L"`, `"mmHg"`).
    public let canonicalUnit: String
    /// How many decimal places to show for this marker's values.
    public let decimals: Int
    /// Neutral placeholder prompting the user to copy the range from their own
    /// report. NOT a shipped reference range (see file header). `nil` where a range
    /// makes no sense (e.g. body measurements, notes).
    public let referenceTextHint: String?
    /// Direction hint — ALWAYS `nil` (NOOP makes no value judgement). Present only as
    /// a deliberate, documented placeholder so no caller infers a default of `true`.
    public let higherIsBetter: Bool?
    public let measurementKind: BiomarkerMeasurementKind
    public let domain: BiomarkerDomain

    public init(
        key: String,
        displayName: String,
        category: LabMarkerCategory,
        canonicalUnit: String,
        decimals: Int,
        referenceTextHint: String? = nil,
        higherIsBetter: Bool? = nil,
        measurementKind: BiomarkerMeasurementKind = .measured,
        domain: BiomarkerDomain = .other
    ) {
        self.key = key
        self.displayName = displayName
        self.category = category
        self.canonicalUnit = canonicalUnit
        self.decimals = decimals
        self.referenceTextHint = referenceTextHint
        self.higherIsBetter = higherIsBetter
        self.measurementKind = measurementKind
        self.domain = domain
    }
}

public enum BiomarkerMeasurementKind: String, Sendable, Equatable, Codable { case measured, calculated, derived }
public enum BiomarkerDomain: String, Sendable, Equatable, Codable, CaseIterable {
    case cardiovascular, metabolic, blood, inflammation, liver, kidney, thyroid
    case vitaminsMinerals, iron, hormones, immune, electrolytes, body, other
}

public struct BiomarkerGuidance: Sendable, Equatable, Codable {
    public var summary: String
    public var whyItMatters: String
    public var commonInfluences: [String]
    public var lifestyleConsiderations: [String]
    public var relatedMarkers: [String]
    public var whenToDiscussWithClinician: String
    public var sources: [BiomarkerKnowledgeSource]
    public var version: String
}

public struct BiomarkerKnowledgeSource: Sendable, Equatable, Codable {
    public var authority: String
    public var title: String
    public var url: String
    public var reviewedOn: String
}

// MARK: - Reference-range and classification foundation

/// A typed reference interval. NOOP currently creates these only by parsing the range the user
/// copied from the same laboratory report as the result. Centrally configured rules can use the
/// same model later, but must carry their own versioned provenance.
public struct BiomarkerReferenceRange: Sendable, Equatable, Codable {
    public enum Source: Sendable, Equatable, Codable {
        case labReport(verbatim: String)
        case configured(authority: String, citation: String, version: String)
    }

    public var lowerBound: Double?
    public var upperBound: Double?
    public var lowerInclusive: Bool
    public var upperInclusive: Bool
    public var unit: String
    public var source: Source

    // Applicability fields are explicit even though report-provided ranges do not need matching:
    // they prevent a future configured rule from silently losing its clinical context.
    public var sexApplicability: String?
    public var minimumAge: Double?
    public var maximumAge: Double?
    public var fastingApplicability: Bool?
    public var pregnancyApplicability: Bool?
    public var assayApplicability: String?
    public var specimenApplicability: String?
    public var timeOfDayApplicability: String?

    public init(lowerBound: Double?, upperBound: Double?, lowerInclusive: Bool = true,
                upperInclusive: Bool = true, unit: String, source: Source,
                sexApplicability: String? = nil, minimumAge: Double? = nil,
                maximumAge: Double? = nil, fastingApplicability: Bool? = nil,
                pregnancyApplicability: Bool? = nil, assayApplicability: String? = nil,
                specimenApplicability: String? = nil, timeOfDayApplicability: String? = nil) {
        self.lowerBound = lowerBound
        self.upperBound = upperBound
        self.lowerInclusive = lowerInclusive
        self.upperInclusive = upperInclusive
        self.unit = unit
        self.source = source
        self.sexApplicability = sexApplicability
        self.minimumAge = minimumAge
        self.maximumAge = maximumAge
        self.fastingApplicability = fastingApplicability
        self.pregnancyApplicability = pregnancyApplicability
        self.assayApplicability = assayApplicability
        self.specimenApplicability = specimenApplicability
        self.timeOfDayApplicability = timeOfDayApplicability
    }
}

/// Clinical relation to an applicable reference interval. This is deliberately separate from the
/// WHOOP-like wellness vocabulary: `within` never means `optimal`.
public enum BiomarkerClinicalRangeStatus: String, Sendable, Equatable, Codable {
    case below, within, above, unknown
}

public enum BiomarkerWellnessStatus: String, Sendable, Equatable, Codable {
    case optimal, sufficient, outOfRange, unknown
}

public enum BiomarkerAttentionPriority: String, Sendable, Equatable, Codable { case none, attention, unknown }

/// Versioned presentation-only fallback for trustworthy result-attached ranges. It never changes
/// the clinical relation and does not claim that the middle of a lab interval is medically optimal.
public enum RangeRelativeWellnessPolicy {
    public static let version = "bounded-central-band-v1"
    public static let centralBand = 0.20...0.80

    public static func classify(value: Double?, range: BiomarkerReferenceRange?,
                                clinicalStatus: BiomarkerClinicalRangeStatus) -> BiomarkerWellnessStatus {
        guard let value, value.isFinite, let range else { return .unknown }
        if clinicalStatus == .below || clinicalStatus == .above { return .outOfRange }
        guard clinicalStatus == .within else { return .unknown }
        guard let lower = range.lowerBound, let upper = range.upperBound, upper > lower else {
            return .sufficient
        }
        let position = (value - lower) / (upper - lower)
        return centralBand.contains(position) ? .optimal : .sufficient
    }
}

/// Geometry policy shared by every range rail and its regression tests. Bounded intervals reserve
/// 22% on each side; one-sided intervals reserve 28% beyond their threshold. Overflow is capped at
/// one interval/threshold-scale so extreme values remain visible without distorting the rail.
public enum BiomarkerRangeRailPolicy {
    public struct Layout: Sendable, Equatable {
        public var acceptableStart: Double
        public var acceptableEnd: Double
        public var markerFraction: Double?
    }

    public static func layout(value: Double?, range: BiomarkerReferenceRange?) -> Layout? {
        guard let range else { return nil }
        let marker: Double?
        switch (range.lowerBound, range.upperBound) {
        case let (lower?, upper?) where upper > lower:
            let start = 0.22, end = 0.78, span = upper - lower
            if let value {
                if value < lower { marker = start * (1 - min((lower - value) / span, 1)) }
                else if value > upper { marker = end + (1 - end) * min((value - upper) / span, 1) }
                else { marker = start + (end - start) * ((value - lower) / span) }
            } else { marker = nil }
            return .init(acceptableStart: start, acceptableEnd: end, markerFraction: marker)
        case let (nil, upper?):
            let threshold = 0.72, scale = max(abs(upper), 1)
            if let value {
                if value > upper { marker = threshold + (1 - threshold) * min((value - upper) / scale, 1) }
                else { marker = threshold * (1 - min((upper - value) / scale, 1)) }
            } else { marker = nil }
            return .init(acceptableStart: 0, acceptableEnd: threshold, markerFraction: marker)
        case let (lower?, nil):
            let threshold = 0.28, scale = max(abs(lower), 1)
            if let value {
                if value < lower { marker = threshold * (1 - min((lower - value) / scale, 1)) }
                else { marker = threshold + (1 - threshold) * min((value - lower) / scale, 1) }
            } else { marker = nil }
            return .init(acceptableStart: threshold, acceptableEnd: 1, markerFraction: marker)
        default:
            return .init(acceptableStart: 0, acceptableEnd: 1, markerFraction: value == nil ? nil : 0.5)
        }
    }
}

public struct BiomarkerResultEvaluation: Sendable, Equatable {
    public var markerKey: String
    public var clinicalStatus: BiomarkerClinicalRangeStatus
    public var wellnessStatus: BiomarkerWellnessStatus
    public var attentionPriority: BiomarkerAttentionPriority
    public var range: BiomarkerReferenceRange?
    public var reason: String
}

public enum BiomarkerUnitNormalizer {
    public struct Normalized: Sendable, Equatable { public var value: Double; public var unit: String }

    public static func normalize(value: Double, unit: String, markerKey: String) -> Normalized? {
        guard value.isFinite, let definition = MarkerCatalog.definition(for: markerKey) else { return nil }
        let from = unitKey(unit), to = unitKey(definition.canonicalUnit)
        if from == to { return Normalized(value: value, unit: definition.canonicalUnit) }
        switch markerKey {
        case "fasting_glucose":
            if from == "mg/dl", to == "mmol/l" { return .init(value: value / 18, unit: definition.canonicalUnit) }
            if from == "mmol/l", to == "mg/dl" { return .init(value: value * 18, unit: definition.canonicalUnit) }
        case "total_cholesterol", "ldl", "hdl":
            if from == "mg/dl", to == "mmol/l" { return .init(value: value / 38.67, unit: definition.canonicalUnit) }
        case "triglycerides":
            if from == "mg/dl", to == "mmol/l" { return .init(value: value / 88.57, unit: definition.canonicalUnit) }
        case "hba1c":
            if from == "%", to == "mmol/mol" { return .init(value: (value - 2.15) * 10.929, unit: definition.canonicalUnit) }
        case "creatinine":
            if from == "mg/dl", to == "umol/l" { return .init(value: value * 88.4, unit: definition.canonicalUnit) }
        case "vitamin_d":
            if from == "ng/ml", to == "nmol/l" { return .init(value: value * 2.5, unit: definition.canonicalUnit) }
        default: break
        }
        return nil
    }

    public static func convertedRange(_ range: BiomarkerReferenceRange, markerKey: String) -> BiomarkerReferenceRange? {
        guard let anchor = range.lowerBound ?? range.upperBound,
              let convertedAnchor = normalize(value: anchor, unit: range.unit, markerKey: markerKey) else { return nil }
        func convert(_ value: Double?) -> Double? {
            value.flatMap { normalize(value: $0, unit: range.unit, markerKey: markerKey)?.value }
        }
        var output = range
        output.lowerBound = convert(range.lowerBound)
        output.upperBound = convert(range.upperBound)
        output.unit = convertedAnchor.unit
        return output
    }

    private static func unitKey(_ unit: String) -> String {
        unit.folding(options: .diacriticInsensitive, locale: .init(identifier: "en_US_POSIX"))
            .lowercased().replacingOccurrences(of: "µ", with: "u").replacingOccurrences(of: "μ", with: "u")
            .replacingOccurrences(of: " ", with: "")
    }
}

public enum BiomarkerEvaluator {
    public static func evaluate(markerKey rawKey: String, value: Double?, unit: String,
                                reportRangeText: String?, configuredRange: BiomarkerReferenceRange? = nil) -> BiomarkerResultEvaluation {
        let key = MarkerCatalog.canonicalKey(for: rawKey) ?? rawKey
        let report = BiomarkerReferenceClassifier.labReportRange(reportRangeText, unit: unit)
        let selected = report ?? configuredRange
        let normalizedValue = value.flatMap { BiomarkerUnitNormalizer.normalize(value: $0, unit: unit, markerKey: key)?.value } ?? value
        let normalizedRange = selected.flatMap { BiomarkerUnitNormalizer.convertedRange($0, markerKey: key) } ?? selected
        let clinical = BiomarkerReferenceClassifier.classify(value: normalizedValue, range: normalizedRange)
        // Marker-specific reviewed wellness rules take precedence here when introduced. Until then,
        // the single versioned range-relative fallback owns all presentation-tier decisions.
        let wellness = RangeRelativeWellnessPolicy.classify(value: normalizedValue, range: normalizedRange,
                                                            clinicalStatus: clinical)
        let attention: BiomarkerAttentionPriority = wellness == .outOfRange ? .attention : clinical == .unknown ? .unknown : .none
        let sourceReason: String
        if report != nil { sourceReason = "Compared with the reference range saved from this result's lab report." }
        else if configuredRange != nil { sourceReason = "Compared with a reviewed configured reference rule." }
        else { sourceReason = "No applicable reference range is available." }
        return .init(markerKey: key, clinicalStatus: clinical, wellnessStatus: wellness,
                     attentionPriority: attention, range: selected, reason: sourceReason)
    }
}

public struct BiomarkerRecordedResult: Sendable, Equatable {
    public var markerKey: String
    public var value: Double?
    public var unit: String
    public var reportRangeText: String?
    public var timestamp: Date
    public init(markerKey: String, value: Double?, unit: String, reportRangeText: String?, timestamp: Date) {
        self.markerKey = markerKey; self.value = value; self.unit = unit
        self.reportRangeText = reportRangeText; self.timestamp = timestamp
    }
}

public struct AdvancedLabsClassificationSummary: Sendable, Equatable {
    public var evaluations: [BiomarkerResultEvaluation]
    public var recordedCount: Int { evaluations.count }
    public var optimalCount: Int { evaluations.filter { $0.wellnessStatus == .optimal }.count }
    public var sufficientCount: Int { evaluations.filter { $0.wellnessStatus == .sufficient }.count }
    public var outOfRangeCount: Int { evaluations.filter { $0.wellnessStatus == .outOfRange }.count }
    public var unclassifiedCount: Int { evaluations.filter { $0.wellnessStatus == .unknown }.count }

    public static func build(results: [BiomarkerRecordedResult]) -> AdvancedLabsClassificationSummary {
        var latest: [String: BiomarkerRecordedResult] = [:]
        for result in results {
            let key = MarkerCatalog.canonicalKey(for: result.markerKey) ?? result.markerKey
            var canonical = result; canonical.markerKey = key
            if latest[key] == nil || canonical.timestamp > latest[key]!.timestamp { latest[key] = canonical }
        }
        return .init(evaluations: latest.values.sorted { $0.markerKey < $1.markerKey }.map {
            BiomarkerEvaluator.evaluate(markerKey: $0.markerKey, value: $0.value, unit: $0.unit,
                                        reportRangeText: $0.reportRangeText)
        })
    }
}

public enum BiomarkerReferenceClassifier {
    public static func classify(value: Double?, range: BiomarkerReferenceRange?) -> BiomarkerClinicalRangeStatus {
        guard let value, value.isFinite, let range else { return .unknown }
        if let lower = range.lowerBound,
           value < lower || (!range.lowerInclusive && value == lower) { return .below }
        if let upper = range.upperBound,
           value > upper || (!range.upperInclusive && value == upper) { return .above }
        return .within
    }

    /// Strictly parses common report forms: `3.0-5.0`, `< 5`, `<= 5`, `> 3`, `>= 3`.
    /// Ambiguous prose stays unavailable instead of being guessed.
    public static func labReportRange(_ text: String?, unit: String) -> BiomarkerReferenceRange? {
        guard let original = text?.trimmingCharacters(in: .whitespacesAndNewlines), !original.isEmpty else { return nil }
        let normalized = original.replacingOccurrences(of: "–", with: "-")
            .replacingOccurrences(of: "—", with: "-")
            .replacingOccurrences(of: ",", with: ".")
        let number = "([+-]?(?:[0-9]+(?:\\.[0-9]*)?|\\.[0-9]+))"

        if let match = captures("^\\s*" + number + "\\s*-\\s*" + number + "(?:\\s+.*)?$", in: normalized),
           match.count == 2, let lower = Double(match[0]), let upper = Double(match[1]), lower <= upper {
            return BiomarkerReferenceRange(lowerBound: lower, upperBound: upper, unit: unit,
                                            source: .labReport(verbatim: original))
        }
        if let match = captures("^\\s*(<=|<|>=|>)\\s*" + number + "(?:\\s+.*)?$", in: normalized),
           match.count == 2, let limit = Double(match[1]) {
            switch match[0] {
            case "<":  return BiomarkerReferenceRange(lowerBound: nil, upperBound: limit,
                                                        upperInclusive: false, unit: unit,
                                                        source: .labReport(verbatim: original))
            case "<=": return BiomarkerReferenceRange(lowerBound: nil, upperBound: limit,
                                                        unit: unit, source: .labReport(verbatim: original))
            case ">":  return BiomarkerReferenceRange(lowerBound: limit, upperBound: nil,
                                                        lowerInclusive: false, unit: unit,
                                                        source: .labReport(verbatim: original))
            default:   return BiomarkerReferenceRange(lowerBound: limit, upperBound: nil,
                                                        unit: unit, source: .labReport(verbatim: original))
            }
        }
        return nil
    }

    private static func captures(_ pattern: String, in text: String) -> [String]? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              match.range.location != NSNotFound else { return nil }
        return (1..<match.numberOfRanges).compactMap { index in
            guard let range = Range(match.range(at: index), in: text) else { return nil }
            return String(text[range])
        }
    }
}

/// The built-in, non-diagnostic marker dictionary. Extensible at runtime via custom
/// markers — see `custom(key:displayName:unit:)`.
public enum MarkerCatalog {

    /// A neutral hint shown in the range field — the user copies their own report's
    /// range here; NOOP ships none.
    private static let fromReport = "From your own report (optional)"

    /// ~30 common markers across the categories. Order is the suggested picker order.
    /// Reference hints are neutral prompts only; `higherIsBetter` is `nil` everywhere.
    public static let builtIn: [MarkerDefinition] = [
        // Lipids (blood panel)
        .init(key: "total_cholesterol", displayName: "Total cholesterol", category: .bloodPanel, canonicalUnit: "mmol/L", decimals: 2, referenceTextHint: fromReport),
        .init(key: "ldl", displayName: "LDL cholesterol", category: .bloodPanel, canonicalUnit: "mmol/L", decimals: 2, referenceTextHint: fromReport),
        .init(key: "hdl", displayName: "HDL cholesterol", category: .bloodPanel, canonicalUnit: "mmol/L", decimals: 2, referenceTextHint: fromReport),
        .init(key: "triglycerides", displayName: "Triglycerides", category: .bloodPanel, canonicalUnit: "mmol/L", decimals: 2, referenceTextHint: fromReport),
        // Glucose
        .init(key: "fasting_glucose", displayName: "Fasting glucose", category: .bloodPanel, canonicalUnit: "mmol/L", decimals: 1, referenceTextHint: fromReport),
        .init(key: "hba1c", displayName: "HbA1c", category: .bloodPanel, canonicalUnit: "mmol/mol", decimals: 0, referenceTextHint: fromReport),
        // Iron studies
        .init(key: "ferritin", displayName: "Ferritin", category: .bloodPanel, canonicalUnit: "µg/L", decimals: 0, referenceTextHint: fromReport),
        .init(key: "iron", displayName: "Serum iron", category: .bloodPanel, canonicalUnit: "µmol/L", decimals: 1, referenceTextHint: fromReport),
        .init(key: "transferrin_saturation", displayName: "Transferrin saturation", category: .bloodPanel, canonicalUnit: "%", decimals: 0, referenceTextHint: fromReport),
        .init(key: "haemoglobin", displayName: "Haemoglobin", category: .bloodPanel, canonicalUnit: "g/L", decimals: 0, referenceTextHint: fromReport),
        // Vitamins
        .init(key: "vitamin_d", displayName: "Vitamin D", category: .bloodPanel, canonicalUnit: "nmol/L", decimals: 0, referenceTextHint: fromReport),
        .init(key: "vitamin_b12", displayName: "Vitamin B12", category: .bloodPanel, canonicalUnit: "ng/L", decimals: 0, referenceTextHint: fromReport),
        .init(key: "folate", displayName: "Folate", category: .bloodPanel, canonicalUnit: "µg/L", decimals: 1, referenceTextHint: fromReport),
        // Thyroid
        .init(key: "tsh", displayName: "TSH", category: .bloodPanel, canonicalUnit: "mIU/L", decimals: 2, referenceTextHint: fromReport),
        .init(key: "free_t4", displayName: "Free T4", category: .bloodPanel, canonicalUnit: "pmol/L", decimals: 1, referenceTextHint: fromReport),
        // Inflammation
        .init(key: "crp", displayName: "C-reactive protein (CRP)", category: .bloodPanel, canonicalUnit: "mg/L", decimals: 1, referenceTextHint: fromReport),
        // Kidney
        .init(key: "egfr", displayName: "eGFR", category: .bloodPanel, canonicalUnit: "mL/min/1.73m²", decimals: 0, referenceTextHint: fromReport),
        .init(key: "creatinine", displayName: "Creatinine", category: .bloodPanel, canonicalUnit: "µmol/L", decimals: 0, referenceTextHint: fromReport),
        // Liver
        .init(key: "alt", displayName: "ALT", category: .bloodPanel, canonicalUnit: "U/L", decimals: 0, referenceTextHint: fromReport),
        .init(key: "ast", displayName: "AST", category: .bloodPanel, canonicalUnit: "U/L", decimals: 0, referenceTextHint: fromReport),
        .init(key: "ggt", displayName: "GGT", category: .bloodPanel, canonicalUnit: "U/L", decimals: 0, referenceTextHint: fromReport),
        // Electrolytes
        .init(key: "sodium", displayName: "Sodium", category: .bloodPanel, canonicalUnit: "mmol/L", decimals: 0, referenceTextHint: fromReport),
        .init(key: "potassium", displayName: "Potassium", category: .bloodPanel, canonicalUnit: "mmol/L", decimals: 1, referenceTextHint: fromReport),
        // Blood pressure (the paired marker — see LabBookProjection.bpSystolicKey/bpDiastolicKey)
        .init(key: "bp_systolic", displayName: "Blood pressure (systolic)", category: .bloodPressure, canonicalUnit: "mmHg", decimals: 0, referenceTextHint: fromReport),
        .init(key: "bp_diastolic", displayName: "Blood pressure (diastolic)", category: .bloodPressure, canonicalUnit: "mmHg", decimals: 0, referenceTextHint: fromReport),
        .init(key: "resting_pulse", displayName: "Resting pulse", category: .bloodPressure, canonicalUnit: "bpm", decimals: 0, referenceTextHint: fromReport),
        // Body measurements
        .init(key: "weight", displayName: "Weight", category: .bodyMeasurement, canonicalUnit: "kg", decimals: 1),
        .init(key: "body_fat", displayName: "Body fat", category: .bodyMeasurement, canonicalUnit: "%", decimals: 1),
        .init(key: "waist", displayName: "Waist circumference", category: .bodyMeasurement, canonicalUnit: "cm", decimals: 1),
        .init(key: "height", displayName: "Height", category: .bodyMeasurement, canonicalUnit: "cm", decimals: 1),

        // CBC / differential (one stable identity per biological marker)
        .init(key: "wbc", displayName: "White blood cell count", category: .bloodPanel, canonicalUnit: "G/L", decimals: 2, referenceTextHint: fromReport, domain: .blood),
        .init(key: "neutrophils_pct", displayName: "Neutrophils", category: .bloodPanel, canonicalUnit: "%", decimals: 1, referenceTextHint: fromReport, domain: .blood),
        .init(key: "lymphocytes_pct", displayName: "Lymphocytes", category: .bloodPanel, canonicalUnit: "%", decimals: 1, referenceTextHint: fromReport, domain: .blood),
        .init(key: "monocytes_pct", displayName: "Monocytes", category: .bloodPanel, canonicalUnit: "%", decimals: 1, referenceTextHint: fromReport, domain: .blood),
        .init(key: "eosinophils_pct", displayName: "Eosinophils", category: .bloodPanel, canonicalUnit: "%", decimals: 1, referenceTextHint: fromReport, domain: .blood),
        .init(key: "basophils_pct", displayName: "Basophils", category: .bloodPanel, canonicalUnit: "%", decimals: 1, referenceTextHint: fromReport, domain: .blood),
        .init(key: "immature_granulocytes_pct", displayName: "Immature granulocytes", category: .bloodPanel, canonicalUnit: "%", decimals: 1, referenceTextHint: fromReport, domain: .blood),
        .init(key: "neutrophils_abs", displayName: "Absolute neutrophils", category: .bloodPanel, canonicalUnit: "G/L", decimals: 2, referenceTextHint: fromReport, domain: .blood),
        .init(key: "lymphocytes_abs", displayName: "Absolute lymphocytes", category: .bloodPanel, canonicalUnit: "G/L", decimals: 2, referenceTextHint: fromReport, domain: .blood),
        .init(key: "monocytes_abs", displayName: "Absolute monocytes", category: .bloodPanel, canonicalUnit: "G/L", decimals: 2, referenceTextHint: fromReport, domain: .blood),
        .init(key: "eosinophils_abs", displayName: "Absolute eosinophils", category: .bloodPanel, canonicalUnit: "G/L", decimals: 2, referenceTextHint: fromReport, domain: .blood),
        .init(key: "basophils_abs", displayName: "Absolute basophils", category: .bloodPanel, canonicalUnit: "G/L", decimals: 2, referenceTextHint: fromReport, domain: .blood),
        .init(key: "immature_granulocytes_abs", displayName: "Absolute immature granulocytes", category: .bloodPanel, canonicalUnit: "G/L", decimals: 2, referenceTextHint: fromReport, domain: .blood),
        .init(key: "rbc", displayName: "Red blood cell count", category: .bloodPanel, canonicalUnit: "T/L", decimals: 2, referenceTextHint: fromReport, domain: .blood),
        .init(key: "hematocrit", displayName: "Hematocrit", category: .bloodPanel, canonicalUnit: "%", decimals: 1, referenceTextHint: fromReport, domain: .blood),
        .init(key: "mcv", displayName: "MCV", category: .bloodPanel, canonicalUnit: "fL", decimals: 1, referenceTextHint: fromReport, domain: .blood),
        .init(key: "mch", displayName: "MCH", category: .bloodPanel, canonicalUnit: "pg", decimals: 1, referenceTextHint: fromReport, domain: .blood),
        .init(key: "mchc", displayName: "MCHC", category: .bloodPanel, canonicalUnit: "g/L", decimals: 0, referenceTextHint: fromReport, domain: .blood),
        .init(key: "rdw", displayName: "RDW", category: .bloodPanel, canonicalUnit: "%", decimals: 1, referenceTextHint: fromReport, domain: .blood),
        .init(key: "platelets", displayName: "Platelets", category: .bloodPanel, canonicalUnit: "G/L", decimals: 0, referenceTextHint: fromReport, domain: .blood),
        .init(key: "mpv", displayName: "MPV", category: .bloodPanel, canonicalUnit: "fL", decimals: 1, referenceTextHint: fromReport, domain: .blood),

        // Additional common panel markers
        .init(key: "fasting_insulin", displayName: "Fasting insulin", category: .bloodPanel, canonicalUnit: "µIU/mL", decimals: 1, referenceTextHint: fromReport, domain: .metabolic),
        .init(key: "homa_ir", displayName: "HOMA-IR", category: .bloodPanel, canonicalUnit: "index", decimals: 2, referenceTextHint: fromReport, measurementKind: .derived, domain: .metabolic),
        .init(key: "magnesium", displayName: "Magnesium", category: .bloodPanel, canonicalUnit: "mmol/L", decimals: 2, referenceTextHint: fromReport, domain: .electrolytes),
        .init(key: "total_bilirubin", displayName: "Total bilirubin", category: .bloodPanel, canonicalUnit: "µmol/L", decimals: 1, referenceTextHint: fromReport, domain: .liver),
        .init(key: "alp", displayName: "Alkaline phosphatase (ALP)", category: .bloodPanel, canonicalUnit: "U/L", decimals: 0, referenceTextHint: fromReport, domain: .liver),
        .init(key: "urea", displayName: "Urea", category: .bloodPanel, canonicalUnit: "mmol/L", decimals: 1, referenceTextHint: fromReport, domain: .kidney),
        .init(key: "cortisol", displayName: "Cortisol", category: .bloodPanel, canonicalUnit: "nmol/L", decimals: 0, referenceTextHint: fromReport, domain: .hormones),
        .init(key: "apob", displayName: "Apolipoprotein B", category: .bloodPanel, canonicalUnit: "g/L", decimals: 2, referenceTextHint: fromReport, domain: .cardiovascular),
        .init(key: "lpa", displayName: "Lipoprotein(a)", category: .bloodPanel, canonicalUnit: "nmol/L", decimals: 0, referenceTextHint: fromReport, domain: .cardiovascular),
        .init(key: "albumin", displayName: "Albumin", category: .bloodPanel, canonicalUnit: "g/L", decimals: 1, referenceTextHint: fromReport, domain: .liver),
        .init(key: "total_protein", displayName: "Total protein", category: .bloodPanel, canonicalUnit: "g/L", decimals: 1, referenceTextHint: fromReport, domain: .liver),
        .init(key: "calcium", displayName: "Calcium", category: .bloodPanel, canonicalUnit: "mmol/L", decimals: 2, referenceTextHint: fromReport, domain: .electrolytes),
        .init(key: "chloride", displayName: "Chloride", category: .bloodPanel, canonicalUnit: "mmol/L", decimals: 0, referenceTextHint: fromReport, domain: .electrolytes),
        .init(key: "phosphate", displayName: "Phosphate", category: .bloodPanel, canonicalUnit: "mmol/L", decimals: 2, referenceTextHint: fromReport, domain: .electrolytes),
    ]

    /// Fast lookup by key. Built once from `builtIn`.
    private static let byKey: [String: MarkerDefinition] = {
        var m: [String: MarkerDefinition] = [:]
        for d in builtIn { m[d.key] = d }
        return m
    }()

    /// Central alias map. Keys are normalized with `aliasKey`; values are stable persistence IDs.
    /// Multiple unit representations (notably HbA1c IFCC/NGSP) intentionally resolve to one identity.
    public static let aliases: [String: String] = {
        var map: [String: String] = [:]
        for definition in builtIn {
            map[aliasKey(definition.key)] = definition.key
            map[aliasKey(definition.displayName)] = definition.key
        }
        let groups: [String: [String]] = [
            "wbc": ["white blood cell count", "white blood cells", "fehérvérsejt", "feherversejt"],
            "neutrophils_pct": ["neutrophil %", "neutrophyl %", "neutrofil %"],
            "lymphocytes_pct": ["lymphocyte %", "lymphocyta %", "limfocita %"],
            "monocytes_pct": ["monocyte %", "monocyta %", "monocita %"],
            "eosinophils_pct": ["eosinophil %", "eosinophyl %", "eozinofil %"],
            "basophils_pct": ["basophil %", "basophyl %", "bazofil %"],
            "immature_granulocytes_pct": ["ig %", "immature granulocyte %", "éretlen granulocita %"],
            "neutrophils_abs": ["absolute neutrophils", "neutrophyl abs. szám", "neutrofil abszolút szám"],
            "lymphocytes_abs": ["absolute lymphocytes", "lymphocyta abs. szám", "limfocita abszolút szám"],
            "monocytes_abs": ["absolute monocytes", "monocyta abs. szám"],
            "eosinophils_abs": ["absolute eosinophils", "eosinophyl abs. szám"],
            "basophils_abs": ["absolute basophils", "basophyl abs. szám"],
            "immature_granulocytes_abs": ["absolute immature granulocytes", "ig abs. szám"],
            "rbc": ["red blood cell count", "red blood cells", "vörösvérsejt", "vorosversejt"],
            "haemoglobin": ["hemoglobin", "haemoglobin", "hb"],
            "hematocrit": ["hematocrit", "hematokrit", "hct"],
            "rdw": ["rdw", "vvt eloszlás", "vvt eloszlas"],
            "platelets": ["platelet count", "platelets", "thrombocyta", "trombocita"],
            "hba1c": ["a1c", "hb a1c", "hemoglobin a1c ifcc", "hemoglobin a1c ngsp", "hba1c ifcc", "hba1c ngsp"],
            "fasting_glucose": ["glucose", "fasting glucose", "vércukor éhgyomri", "vercukor ehgyomri"],
            "fasting_insulin": ["insulin", "fasting insulin", "inzulin", "éhgyomri inzulin"],
            "homa_ir": ["homa ir", "homa index", "homa index inzulin rezisztencia"],
            "total_bilirubin": ["total bilirubin", "totál bilirubin", "total bilirubin"],
            "alt": ["alt", "gpt", "sgpt", "alanine aminotransferase"],
            "ast": ["ast", "got", "sgot", "aspartate aminotransferase"],
            "ggt": ["ggt", "gamma gt", "gamma glutamyl transferase"],
            "alp": ["alp", "alkaline phosphatase", "alkalikus foszfatáz", "alkalikus foszfataz"],
            "urea": ["urea", "karbamid"], "creatinine": ["creatinine", "kreatinin"],
            "egfr": ["egfr", "egfr epi", "egfr-epi", "egfr epi ff"],
            "iron": ["iron", "serum iron", "vas"], "ferritin": ["ferritin"],
            "total_cholesterol": ["total cholesterol", "cholesterol", "koleszterin", "totál koleszterin"],
            "triglycerides": ["triglyceride", "triglycerides", "triglicerid"],
            "hdl": ["hdl", "hdl cholesterol", "hdl koleszterin"],
            "ldl": ["ldl", "ldl cholesterol", "ldl koleszterin"],
            "folate": ["folate", "folic acid", "folsav", "folsav b9 vitamin", "b9 vitamin"],
            "vitamin_b12": ["vitamin b12", "b12 vitamin", "b12-vitamin"],
            "vitamin_d": ["vitamin d", "25 oh vitamin d", "25-oh-d-vitamin"],
            "tsh": ["tsh"], "cortisol": ["cortisol", "kortizol"],
            "crp": ["crp", "c reactive protein", "c-reactive protein"],
            "magnesium": ["magnesium", "magnézium", "magnezium"]
        ]
        for (key, names) in groups { for name in names { map[aliasKey(name)] = key } }
        return map
    }()

    public static func canonicalKey(for name: String) -> String? { aliases[aliasKey(name)] }

    public static func domain(for key: String) -> BiomarkerDomain {
        if let explicit = definition(for: key)?.domain, explicit != .other { return explicit }
        if ["total_cholesterol", "ldl", "hdl", "triglycerides", "apob", "lpa"].contains(key) { return .cardiovascular }
        if ["fasting_glucose", "hba1c", "fasting_insulin", "homa_ir"].contains(key) { return .metabolic }
        if ["ferritin", "iron", "transferrin_saturation"].contains(key) { return .iron }
        if ["vitamin_d", "vitamin_b12", "folate", "magnesium"].contains(key) { return .vitaminsMinerals }
        if ["tsh", "free_t4"].contains(key) { return .thyroid }
        if ["crp"].contains(key) { return .inflammation }
        if ["egfr", "creatinine", "urea"].contains(key) { return .kidney }
        if ["alt", "ast", "ggt", "alp", "total_bilirubin", "albumin", "total_protein"].contains(key) { return .liver }
        if key == "cortisol" { return .hormones }
        if ["sodium", "potassium", "calcium", "chloride", "phosphate"].contains(key) { return .electrolytes }
        if key == "haemoglobin" || key == "hematocrit" || key == "rbc" || key == "wbc" || key == "platelets" || key.hasSuffix("_pct") || key.hasSuffix("_abs") || ["mcv", "mch", "mchc", "rdw", "mpv"].contains(key) { return .blood }
        if ["weight", "body_fat", "waist", "height"].contains(key) { return .body }
        return .other
    }

    /// Reviewed educational copy for the initial high-value subset. This is deliberately sparse:
    /// missing content is rendered as unavailable rather than synthesized from a generic template.
    public static func guidance(for rawKey: String) -> BiomarkerGuidance? {
        let key = canonicalKey(for: rawKey) ?? rawKey
        let reviewed = "2026-08-09"
        switch key {
        case "hba1c":
            return .init(summary: "HbA1c reflects the share of haemoglobin with glucose attached.",
                         whyItMatters: "It is commonly used to describe average blood glucose over the preceding months.",
                         commonInfluences: ["Red-blood-cell turnover", "Recent blood loss or transfusion", "Some haemoglobin variants"],
                         lifestyleConsiderations: ["Keep measurement conditions and laboratory method documented when comparing results."],
                         relatedMarkers: ["fasting_glucose"],
                         whenToDiscussWithClinician: "Discuss an unexpected result or a mismatch with glucose readings with a healthcare professional.",
                         sources: [.init(authority: "CDC", title: "About A1C Test", url: "https://www.cdc.gov/diabetes-basics/about/about-a1c-test.html", reviewedOn: reviewed)], version: "1")
        case "ldl", "total_cholesterol", "hdl", "triglycerides":
            return .init(summary: "This marker is part of a lipid panel describing fats and fat-carrying particles in blood.",
                         whyItMatters: "Lipid results are interpreted together with cardiovascular history and other risk factors.",
                         commonInfluences: ["Fasting status for some measurements", "Recent illness", "Genetics and longer-term dietary pattern"],
                         lifestyleConsiderations: ["Compare like-for-like collection conditions and review the full lipid panel together."],
                         relatedMarkers: ["total_cholesterol", "ldl", "hdl", "triglycerides", "apob", "lpa"],
                         whenToDiscussWithClinician: "Discuss results outside the laboratory range or persistent changes with a healthcare professional.",
                         sources: [.init(authority: "NHLBI", title: "Blood Cholesterol", url: "https://www.nhlbi.nih.gov/health/blood-cholesterol", reviewedOn: reviewed)], version: "1")
        case "vitamin_d":
            return .init(summary: "25-hydroxyvitamin D is the main blood marker used to assess vitamin D status.",
                         whyItMatters: "Vitamin D supports calcium handling and bone health.",
                         commonInfluences: ["Season and sun exposure", "Diet", "Absorption and kidney or liver function"],
                         lifestyleConsiderations: ["Record season and collection date when comparing results."],
                         relatedMarkers: ["calcium", "phosphate", "alp"],
                         whenToDiscussWithClinician: "Discuss an out-of-range result before making treatment or supplement decisions.",
                         sources: [.init(authority: "NIH Office of Dietary Supplements", title: "Vitamin D — Health Professional Fact Sheet", url: "https://ods.od.nih.gov/factsheets/VitaminD-HealthProfessional/", reviewedOn: reviewed)], version: "1")
        case "ferritin":
            return .init(summary: "Ferritin is a protein that stores iron and is used as one view of the body's iron stores.",
                         whyItMatters: "It is interpreted alongside blood count, iron studies, symptoms and clinical context.",
                         commonInfluences: ["Inflammation or infection", "Iron status", "Liver conditions"],
                         lifestyleConsiderations: ["Review ferritin together with related iron and inflammation markers."],
                         relatedMarkers: ["iron", "transferrin_saturation", "haemoglobin", "crp"],
                         whenToDiscussWithClinician: "Discuss low, high or changing ferritin with a healthcare professional.",
                         sources: [.init(authority: "MedlinePlus", title: "Ferritin Blood Test", url: "https://medlineplus.gov/lab-tests/ferritin-blood-test/", reviewedOn: reviewed)], version: "1")
        default: return nil
        }
    }

    private static func aliasKey(_ value: String) -> String {
        let folded = value.folding(options: .diacriticInsensitive, locale: .init(identifier: "en_US_POSIX")).lowercased()
        return String(folded.map { $0.isLetter || $0.isNumber ? $0 : "_" })
            .split(separator: "_").joined(separator: "_")
    }

    /// The built-in definition for `key`, or `nil` if it's a custom marker.
    public static func definition(for key: String) -> MarkerDefinition? {
        byKey[key]
    }

    /// Build a definition for a user-added custom marker. Categorised as `.other`
    /// with no reference hint and no direction judgement — the store is never gated
    /// by the built-in dictionary.
    public static func custom(key: String, displayName: String, unit: String, decimals: Int = 1) -> MarkerDefinition {
        MarkerDefinition(
            key: key,
            displayName: displayName,
            category: .other,
            canonicalUnit: unit,
            decimals: decimals,
            referenceTextHint: nil,
            higherIsBetter: nil
        )
    }
}
