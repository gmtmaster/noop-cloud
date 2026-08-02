import Foundation
import StrandAnalytics
import WhoopStore

@MainActor
enum NoopAgeInputBuilder {
    static func evaluate(days: [HealthspanDay], chronologicalAge: Double?, birthDate: Date? = nil) -> [NoopAgeWeekResult] {
        guard let first = days.map(\.day).min() else { return [] }
        let latest = HealthspanWeekCutoff.latestCompletedWeekEnd(now: Date(), calendar: .current)
        var cutoffs: [String] = [], cursor = saturdayKey(onOrAfter: first)
        while cursor <= latest {
            cutoffs.append(cursor)
            guard let date = dayFormatter.date(from: cursor),
                  let next = Calendar.utc.date(byAdding: .day, value: 7, to: date) else { break }
            cursor = dayFormatter.string(from: next)
        }
        return NoopAgeEngine.evaluate(days: days, weekEndDays: cutoffs) { key in
            if let birthDate, let end = dayFormatter.date(from: key), birthDate <= end {
                let p = Calendar.current.dateComponents([.year, .day], from: birthDate, to: end)
                return Double(p.year ?? 0) + Double(p.day ?? 0) / 365.2425
            }
            return chronologicalAge
        }
    }

    static func saturdayKey(onOrBefore day: String) -> String {
        guard let date = dayFormatter.date(from: day) else { return day }
        let weekday = Calendar.utc.component(.weekday, from: date)
        return dayFormatter.string(from: Calendar.utc.date(byAdding: .day, value: -((weekday + 1) % 7), to: date) ?? date)
    }

    static func saturdayKey(onOrAfter day: String) -> String {
        guard let date = dayFormatter.date(from: day) else { return day }
        let weekday = Calendar.utc.component(.weekday, from: date)
        return dayFormatter.string(from: Calendar.utc.date(byAdding: .day, value: (7 - weekday) % 7, to: date) ?? date)
    }

    static func observations(dailies: [DailyMetric], sleeps: [CachedSleepSession],
                             series: [String: [(day: String, value: Double)]]) -> [HealthspanDay] {
        var byDay: [String: HealthspanDay] = [:]
        for d in dailies {
            byDay[d.day] = HealthspanDay(day: d.day, sleepMinutes: d.totalSleepMin,
                steps: d.steps.map(Double.init), restingHR: d.restingHr.map(Double.init))
        }
        // Use the longest real session ending on each local day; naps must not distort bedtime regularity.
        var mainSleep: [String: CachedSleepSession] = [:]
        for s in sleeps where s.endTs > s.effectiveStartTs {
            let day = localDay(Date(timeIntervalSince1970: TimeInterval(s.endTs)))
            if mainSleep[day].map({ $0.endTs - $0.effectiveStartTs }) ?? -1 < s.endTs - s.effectiveStartTs { mainSleep[day] = s }
        }
        for (day, s) in mainSleep {
            var o = byDay[day] ?? HealthspanDay(day: day)
            let start = Date(timeIntervalSince1970: TimeInterval(s.effectiveStartTs))
            let end = Date(timeIntervalSince1970: TimeInterval(s.endTs))
            o.sleepMinutes = o.sleepMinutes ?? Double(s.endTs - s.effectiveStartTs) / 60
            o.sleepStartMinute = localMinute(start); o.wakeMinute = localMinute(end); byDay[day] = o
        }
        func map(_ key: String) -> [String: Double] { Dictionary(uniqueKeysWithValues: (series[key] ?? []).map { ($0.day, $0.value) }) }
        let steps = map("steps"), z1 = map("hr_zone1_min"), z2 = map("hr_zone2_min"), z3 = map("hr_zone3_min")
        let z4 = map("hr_zone4_min"), z5 = map("hr_zone5_min"), strength = map("strength_min")
        let vo2 = map("vo2max"), vo2Estimated = map("vo2max_est"), lean = map("lean_mass"), weight = map("weight")
        let allDays = Set(byDay.keys).union(steps.keys).union(z1.keys).union(z2.keys).union(z3.keys)
            .union(z4.keys).union(z5.keys).union(strength.keys).union(vo2.keys).union(vo2Estimated.keys)
            .union(lean.keys).union(weight.keys)
        for day in allDays {
            var o = byDay[day] ?? HealthspanDay(day: day)
            o.steps = o.steps ?? steps[day]
            let low = [z1[day], z2[day], z3[day]].compactMap { $0 }
            let high = [z4[day], z5[day]].compactMap { $0 }
            if !low.isEmpty { o.zone1to3Minutes = low.reduce(0, +) }
            if !high.isEmpty { o.zone4to5Minutes = high.reduce(0, +) }
            o.strengthMinutes = strength[day]; o.vo2Max = vo2[day] ?? vo2Estimated[day]
            if let l = lean[day], let w = weight[day], w > 0, l > 0, l <= w { o.leanMassPercent = l / w * 100 }
            byDay[day] = o
        }
        return byDay.values.sorted { $0.day < $1.day }
    }

    private static func localDay(_ d: Date) -> String { localDayFormatter.string(from: d) }
    private static func localMinute(_ d: Date) -> Double {
        let p = Calendar.current.dateComponents([.hour, .minute, .second], from: d)
        return Double((p.hour ?? 0) * 60 + (p.minute ?? 0)) + Double(p.second ?? 0) / 60
    }
    private static let dayFormatter: DateFormatter = { let f = DateFormatter(); f.calendar = Calendar.utc
        f.locale = Locale(identifier: "en_US_POSIX"); f.timeZone = TimeZone(secondsFromGMT: 0); f.dateFormat = "yyyy-MM-dd"; return f }()
    private static let localDayFormatter: DateFormatter = { let f = DateFormatter(); f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX"); f.timeZone = .current; f.dateFormat = "yyyy-MM-dd"; return f }()
}

extension Repository {
    func noopAgeHistory(profile: ProfileStore) async -> [NoopAgeWeekResult] {
        async let steps = exploreSeries(key: "steps", source: "my-whoop")
        async let z1 = exploreSeries(key: "hr_zone1_min", source: "my-whoop")
        async let z2 = exploreSeries(key: "hr_zone2_min", source: "my-whoop")
        async let z3 = exploreSeries(key: "hr_zone3_min", source: "my-whoop")
        async let z4 = exploreSeries(key: "hr_zone4_min", source: "my-whoop")
        async let z5 = exploreSeries(key: "hr_zone5_min", source: "my-whoop")
        async let strength = exploreSeries(key: "strength_min", source: "my-whoop")
        async let vo2 = exploreSeries(key: "vo2max", source: "apple-health")
        async let vo2est = exploreSeries(key: "vo2max_est", source: "my-whoop")
        async let lean = exploreSeries(key: "lean_mass", source: "apple-health")
        async let weight = exploreSeries(key: "weight", source: "apple-health")
        let series = await ["steps": steps, "hr_zone1_min": z1, "hr_zone2_min": z2, "hr_zone3_min": z3,
            "hr_zone4_min": z4, "hr_zone5_min": z5, "strength_min": strength, "vo2max": vo2,
            "vo2max_est": vo2est, "lean_mass": lean, "weight": weight]
        let observations = NoopAgeInputBuilder.observations(dailies: days, sleeps: sleeps, series: series)
        let age = profile.ageIsExplicit && profile.age > 0 ? Double(profile.age) : nil
        let results = NoopAgeInputBuilder.evaluate(days: observations, chronologicalAge: age, birthDate: profile.birthDate)
        // Canonical weekly projection for Trends and every other generic metric consumer. These keys are
        // deliberately distinct from legacy fitness_age/body_age/vitality and contain exactly the values
        // returned to Healthspan and Today above.
        if let store = await storeHandle() {
            let points = results.flatMap { result -> [MetricPoint] in
                NoopAgeEngine.canonicalMetricValues(result).map {
                    MetricPoint(day: result.weekEndDay, key: $0.key, value: $0.value)
                }
            }
            if !points.isEmpty { _ = try? await store.upsertMetricSeries(points, deviceId: Repository.whoopSource + "-noop") }
        }
        return results
    }
}

private extension Calendar {
    static var utc: Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(secondsFromGMT: 0)!; return c }
}
