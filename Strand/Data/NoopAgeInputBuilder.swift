import Foundation
import StrandAnalytics
import WhoopStore

@MainActor
enum NoopAgeInputBuilder {
    static func evaluate(days: [DailyMetric], chronologicalAge: Double?, birthDate: Date? = nil, sex: String,
                         debtByDay: [String: Double] = [:]) -> [NoopAgeWeekResult] {
        let valid = days.sorted { $0.day < $1.day }
        let grouped = Dictionary(grouping: valid) { saturdayKey(onOrAfter: $0.day) }
        // A Saturday is not complete until midnight. Anchor on yesterday before finding the prior
        // Saturday so forward navigation can never expose a still-forming week.
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date()) ?? Date()
        let latestCompletedWeek = saturdayKey(onOrBefore: dayFormatter.string(from: yesterday))
        let inputs = grouped.keys.filter { $0 <= latestCompletedWeek }.sorted().map { key -> NoopAgeWeekInput in
            let rows = grouped[key] ?? []
            let ageAtWeek: Double? = birthDate.flatMap { birth in
                guard let end = dayFormatter.date(from: key), birth <= end else { return nil }
                let parts = Calendar.current.dateComponents([.year, .day], from: birth, to: end)
                return Double(parts.year ?? 0) + Double(parts.day ?? 0) / 365.2425
            } ?? chronologicalAge
            return NoopAgeWeekInput(
                weekEndDay: key, chronologicalAge: ageAtWeek, sex: sex,
                restingHR: rows.compactMap { $0.restingHr.map(Double.init) },
                strain: rows.compactMap(\.strain), hrv: rows.compactMap(\.avgHrv),
                sleepMinutes: rows.compactMap(\.totalSleepMin),
                recentSleepDebtMinutes: rows.reversed().compactMap { debtByDay[$0.day] }.first,
                recovery: rows.compactMap(\.recovery),
                workoutCount: rows.compactMap(\.exerciseCount).reduce(0, +))
        }
        return NoopAgeEngine.evaluate(inputs)
    }

    static func saturdayKey(onOrBefore day: String) -> String {
        guard let date = dayFormatter.date(from: day) else { return day }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let weekday = calendar.component(.weekday, from: date)
        let daysSinceSaturday = (weekday + 1) % 7
        return dayFormatter.string(from: calendar.date(byAdding: .day, value: -daysSinceSaturday, to: date) ?? date)
    }

    static func saturdayKey(onOrAfter day: String) -> String {
        guard let date = dayFormatter.date(from: day) else { return day }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let weekday = calendar.component(.weekday, from: date)
        let daysUntilSaturday = (7 - weekday) % 7
        return dayFormatter.string(from: calendar.date(byAdding: .day, value: daysUntilSaturday, to: date) ?? date)
    }

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}

extension Repository {
    func noopAgeHistory(profile: ProfileStore) async -> [NoopAgeWeekResult] {
        let sleep = await sleepPlanningResult()
        let debt = Dictionary(uniqueKeysWithValues: sleep.history.compactMap { point in
            point.recentDebtMinutes.map { (point.day, $0) }
        })
        let age = profile.ageIsExplicit && profile.age > 0 ? Double(profile.age) : nil
        return NoopAgeInputBuilder.evaluate(days: days, chronologicalAge: age, birthDate: profile.birthDate,
                                            sex: profile.sex, debtByDay: debt)
    }
}
