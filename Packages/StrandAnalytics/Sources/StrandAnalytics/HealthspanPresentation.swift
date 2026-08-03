import Foundation

public enum HealthspanWeekCutoff {
    /// Most recent fully completed Saturday in the supplied local calendar.
    public static func latestCompletedWeekEnd(now: Date, calendar input: Calendar) -> String {
        let calendar = input
        let today = calendar.startOfDay(for: now)
        let previousDay = calendar.date(byAdding: .day, value: -1, to: today)!
        let weekday = calendar.component(.weekday, from: previousDay)
        let daysBack = weekday % 7
        let saturday = calendar.date(byAdding: .day, value: -daysBack, to: previousDay)!
        let parts = calendar.dateComponents([.year, .month, .day], from: saturday)
        return String(format: "%04d-%02d-%02d", parts.year!, parts.month!, parts.day!)
    }
}

public enum HealthspanContributorAvailability: Equatable, Sendable {
    case buildingPaceBaseline
    case insufficientComparableData
    case valid

    public static func resolve(_ result: NoopAgeWeekResult) -> Self {
        if result.paceOfAging == nil { return .buildingPaceBaseline }
        if result.contributors.isEmpty || result.coverage.representedDomains < 2 {
            return .insufficientComparableData
        }
        return .valid
    }
}

public enum HealthspanDirection: Equatable, Sendable {
    case improving, neutral, worsening

    public static func classify(delta: Double) -> Self {
        if delta <= -0.25 { return .improving }
        if delta >= 0.25 { return .worsening }
        return .neutral
    }
}

public enum HealthspanSelection {
    public static func newestIndex(count: Int) -> Int { max(0, count - 1) }
}

public enum HealthspanPacePresentation {
    public static func value(_ pace: Double?) -> String {
        pace.map { String(format: "%.1fx", $0) } ?? "—"
    }

    public static func calibrationDetail(_ eligibility: NoopAgeEngine.PaceEligibility) -> String {
        "Recent window \(min(eligibility.recentWearDays, NoopAgeEngine.Configuration.minimumRecentPaceWearDays)) " +
        "of \(NoopAgeEngine.Configuration.minimumRecentPaceWearDays) · older baseline " +
        "\(min(eligibility.olderWearDays, NoopAgeEngine.Configuration.minimumOlderPaceWearDays)) " +
        "of \(NoopAgeEngine.Configuration.minimumOlderPaceWearDays) · " +
        "\(min(eligibility.validWeeks, NoopAgeEngine.Configuration.minimumPaceWeeks)) " +
        "of \(NoopAgeEngine.Configuration.minimumPaceWeeks) weeks"
    }
}
