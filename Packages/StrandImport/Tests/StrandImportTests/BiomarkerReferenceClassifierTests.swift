import XCTest
@testable import StrandImport

final class BiomarkerReferenceClassifierTests: XCTestCase {
    func testBoundedLabRangeClassification() {
        let range = BiomarkerReferenceClassifier.labReportRange("3.0–5.0 mmol/L", unit: "mmol/L")
        XCTAssertEqual(range?.lowerBound, 3)
        XCTAssertEqual(range?.upperBound, 5)
        XCTAssertEqual(BiomarkerReferenceClassifier.classify(value: 2.9, range: range), .below)
        XCTAssertEqual(BiomarkerReferenceClassifier.classify(value: 4, range: range), .within)
        XCTAssertEqual(BiomarkerReferenceClassifier.classify(value: 5.1, range: range), .above)
    }

    func testOneSidedRangesPreserveShapeAndInclusivity() {
        let upper = BiomarkerReferenceClassifier.labReportRange("< 5 mg/L", unit: "mg/L")
        XCTAssertNil(upper?.lowerBound)
        XCTAssertEqual(upper?.upperBound, 5)
        XCTAssertEqual(BiomarkerReferenceClassifier.classify(value: 5, range: upper), .above)

        let lower = BiomarkerReferenceClassifier.labReportRange(">= 3", unit: "µg/L")
        XCTAssertEqual(BiomarkerReferenceClassifier.classify(value: 3, range: lower), .within)
        XCTAssertEqual(BiomarkerReferenceClassifier.classify(value: 2.9, range: lower), .below)
    }

    func testAmbiguousRangeRemainsUnavailable() {
        XCTAssertNil(BiomarkerReferenceClassifier.labReportRange("normal for this lab", unit: "mg/L"))
        XCTAssertEqual(BiomarkerReferenceClassifier.classify(value: 4, range: nil), .unknown)
    }

    func testCatalogHasSixtyFiveStableUniqueMarkers() {
        XCTAssertEqual(MarkerCatalog.builtIn.count, 65)
        XCTAssertEqual(Set(MarkerCatalog.builtIn.map(\.key)).count, 65)
        XCTAssertEqual(MarkerCatalog.canonicalKey(for: "Vörösvérsejt"), "rbc")
        XCTAssertEqual(MarkerCatalog.canonicalKey(for: "Folsav (B9-vitamin)"), "folate")
        XCTAssertEqual(MarkerCatalog.canonicalKey(for: "Hemoglobin A1C (NGSP)"), "hba1c")
        XCTAssertEqual(MarkerCatalog.canonicalKey(for: "Hemoglobin A1C (IFCC)"), "hba1c")
    }

    func testHungarianDecimalCommaRanges() {
        let range = BiomarkerReferenceClassifier.labReportRange("3,00–5,20", unit: "mmol/L")
        XCTAssertEqual(range?.lowerBound, 3)
        XCTAssertEqual(range?.upperBound, 5.2)
    }

    func testCanonicalUnitConversions() {
        XCTAssertEqual(BiomarkerUnitNormalizer.normalize(value: 90, unit: "mg/dL", markerKey: "fasting_glucose")!.value, 5, accuracy: 0.001)
        XCTAssertEqual(BiomarkerUnitNormalizer.normalize(value: 4.7, unit: "%", markerKey: "hba1c")!.value, 27.87, accuracy: 0.02)
        XCTAssertEqual(BiomarkerUnitNormalizer.normalize(value: 1, unit: "mg/dL", markerKey: "creatinine")!.value, 88.4, accuracy: 0.001)
        XCTAssertEqual(BiomarkerUnitNormalizer.normalize(value: 32.8, unit: "ng/mL", markerKey: "vitamin_d")!.value, 82, accuracy: 0.001)
    }

    func testReportRangeOverridesConfiguredRangeAndUsesRangeRelativePresentation() {
        let configured = BiomarkerReferenceRange(lowerBound: 0, upperBound: 3, unit: "mmol/L",
            source: .configured(authority: "Test", citation: "fixture", version: "1"))
        let result = BiomarkerEvaluator.evaluate(markerKey: "ldl", value: 3.26, unit: "mmol/L",
                                                 reportRangeText: "< 2.59", configuredRange: configured)
        XCTAssertEqual(result.clinicalStatus, .above)
        XCTAssertEqual(result.wellnessStatus, .outOfRange)
        XCTAssertEqual(result.range?.source, .labReport(verbatim: "< 2.59"))

        let within = BiomarkerEvaluator.evaluate(markerKey: "hdl", value: 1.81, unit: "mmol/L",
                                                 reportRangeText: "1.0-3.6")
        XCTAssertEqual(within.clinicalStatus, .within)
        XCTAssertEqual(within.wellnessStatus, .optimal)
    }

    func testRangeRelativeWellnessBoundedAndOneSided() {
        let bounded = BiomarkerReferenceClassifier.labReportRange("0-100", unit: "u")!
        XCTAssertEqual(RangeRelativeWellnessPolicy.classify(value: 0, range: bounded, clinicalStatus: .within), .sufficient)
        XCTAssertEqual(RangeRelativeWellnessPolicy.classify(value: 20, range: bounded, clinicalStatus: .within), .optimal)
        XCTAssertEqual(RangeRelativeWellnessPolicy.classify(value: 50, range: bounded, clinicalStatus: .within), .optimal)
        XCTAssertEqual(RangeRelativeWellnessPolicy.classify(value: 80, range: bounded, clinicalStatus: .within), .optimal)
        XCTAssertEqual(RangeRelativeWellnessPolicy.classify(value: 100, range: bounded, clinicalStatus: .within), .sufficient)
        let upper = BiomarkerReferenceClassifier.labReportRange("< 5", unit: "u")!
        let lower = BiomarkerReferenceClassifier.labReportRange("> 4.6", unit: "u")!
        XCTAssertEqual(RangeRelativeWellnessPolicy.classify(value: 2, range: upper, clinicalStatus: .within), .sufficient)
        XCTAssertEqual(RangeRelativeWellnessPolicy.classify(value: 8, range: lower, clinicalStatus: .within), .sufficient)
    }

    func testRangeRailBoundedPositionsAndExtremeClamping() {
        let range = BiomarkerReferenceClassifier.labReportRange("10-20", unit: "u")!
        let below = BiomarkerRangeRailPolicy.layout(value: 5, range: range)!
        let inside = BiomarkerRangeRailPolicy.layout(value: 15, range: range)!
        let above = BiomarkerRangeRailPolicy.layout(value: 25, range: range)!
        XCTAssertLessThan(below.markerFraction!, below.acceptableStart)
        XCTAssertEqual(inside.markerFraction!, 0.5, accuracy: 0.0001)
        XCTAssertGreaterThan(above.markerFraction!, above.acceptableEnd)
        XCTAssertEqual(BiomarkerRangeRailPolicy.layout(value: -10_000, range: range)!.markerFraction!, 0)
        XCTAssertEqual(BiomarkerRangeRailPolicy.layout(value: 10_000, range: range)!.markerFraction!, 1)
        XCTAssertEqual(BiomarkerRangeRailPolicy.layout(value: 10, range: range)!.markerFraction!, below.acceptableStart)
        XCTAssertEqual(BiomarkerRangeRailPolicy.layout(value: 20, range: range)!.markerFraction!, above.acceptableEnd)
    }

    func testRangeRailOneSidedThresholdPositions() {
        let upper = BiomarkerReferenceClassifier.labReportRange("< 5", unit: "u")!
        let upperLayout = BiomarkerRangeRailPolicy.layout(value: 6, range: upper)!
        XCTAssertGreaterThan(upperLayout.markerFraction!, upperLayout.acceptableEnd)
        XCTAssertEqual(BiomarkerRangeRailPolicy.layout(value: 5, range: upper)!.markerFraction!, upperLayout.acceptableEnd)
        let lower = BiomarkerReferenceClassifier.labReportRange("> 4.6", unit: "u")!
        let lowerLayout = BiomarkerRangeRailPolicy.layout(value: 4, range: lower)!
        XCTAssertLessThan(lowerLayout.markerFraction!, lowerLayout.acceptableStart)
        XCTAssertEqual(BiomarkerRangeRailPolicy.layout(value: 4.6, range: lower)!.markerFraction!, lowerLayout.acceptableStart)
    }

    func testAugust2026PanelFixtureClassificationAndAliasDeduplication() {
        let date = Date(timeIntervalSince1970: 1_786_051_200)
        let fixture: [BiomarkerRecordedResult] = [
            .init(markerKey: "Hemoglobin A1C (IFCC)", value: 28, unit: "mmol/mol", reportRangeText: "20-42", timestamp: date),
            .init(markerKey: "Hemoglobin A1C (NGSP)", value: 4.7, unit: "%", reportRangeText: "4-6", timestamp: date.addingTimeInterval(1)),
            .init(markerKey: "Vércukor (glükóz) éhgyomri", value: 5.2, unit: "mmol/L", reportRangeText: "3-6", timestamp: date),
            .init(markerKey: "Koleszterin", value: 5.60, unit: "mmol/L", reportRangeText: "3-5.2", timestamp: date),
            .init(markerKey: "LDL koleszterin", value: 3.26, unit: "mmol/L", reportRangeText: "< 2.59", timestamp: date),
            .init(markerKey: "Folsav (B9-vitamin)", value: 4.3, unit: "ng/mL", reportRangeText: "> 4.6", timestamp: date),
            .init(markerKey: "Cortisol", value: 560, unit: "nmol/L", reportRangeText: "133-537", timestamp: date),
            .init(markerKey: "CRP", value: 1.7, unit: "mg/L", reportRangeText: "< 5", timestamp: date)
            ,.init(markerKey: "25-OH-D-vitamin", value: 82, unit: "nmol/L", reportRangeText: "75-250", timestamp: date)
            ,.init(markerKey: "B12-vitamin", value: 497, unit: "ng/L", reportRangeText: "197-771", timestamp: date)
            ,.init(markerKey: "Triglicerid", value: 0.86, unit: "mmol/L", reportRangeText: "0.5-1.7", timestamp: date)
            ,.init(markerKey: "Magnézium", value: 0.6, unit: "mmol/L", reportRangeText: "0.73-1.06", timestamp: date)
        ]
        let summary = AdvancedLabsClassificationSummary.build(results: fixture)
        XCTAssertEqual(summary.recordedCount, 11) // the two HbA1c representations are one identity
        XCTAssertEqual(summary.optimalCount, 4)
        XCTAssertEqual(summary.sufficientCount, 2)
        XCTAssertEqual(summary.outOfRangeCount, 5)
        XCTAssertEqual(summary.unclassifiedCount, 0)
        XCTAssertEqual(summary.optimalCount + summary.sufficientCount + summary.outOfRangeCount + summary.unclassifiedCount,
                       summary.recordedCount)
        XCTAssertEqual(summary.evaluations.first { $0.markerKey == "hba1c" }?.clinicalStatus, .within)
        XCTAssertEqual(summary.evaluations.first { $0.markerKey == "vitamin_d" }?.wellnessStatus, .sufficient)
        XCTAssertEqual(summary.evaluations.first { $0.markerKey == "vitamin_b12" }?.wellnessStatus, .optimal)
        XCTAssertEqual(summary.evaluations.first { $0.markerKey == "triglycerides" }?.wellnessStatus, .optimal)
        XCTAssertEqual(summary.evaluations.first { $0.markerKey == "magnesium" }?.attentionPriority, .attention)
    }
}
