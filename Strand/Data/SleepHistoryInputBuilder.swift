import Foundation
import StrandAnalytics
import WhoopStore

/// The sole app-layer adapter from repository sleep records to the analytics planner.
/// It owns day bucketing, main/nap selection, asleep-time estimation, and imported references.
@MainActor
enum SleepHistoryInputBuilder {
    static func build(days: [DailyMetric], sessions: [CachedSleepSession],
                      habitualMidsleepSec: Int?, importedSleep: [String: ImportedSleepFigures],
                      timeZone: TimeZone = .current)
        -> [SleepPlanningNightInput] {
        let grouped = Dictionary(grouping: sessions) {
            Repository.sleepWakeDayKey($0, timeZone: timeZone)
        }
        let parts = grouped.reduce(into: [String: (main: Double, naps: Double)]()) { result, pair in
            let ordered = pair.value.sorted { $0.effectiveStartTs < $1.effectiveStartTs }
            let blocks = ordered.map { SleepStageTotals.NightBlock(start: $0.effectiveStartTs, end: $0.endTs) }
            let mainIndices = SleepStageTotals.mainNightGroupIndices(
                blocks, offsetSec: TimeZone.current.secondsFromGMT(), habitualMidsleepSec: habitualMidsleepSec) ?? []
            let mainStarts = Set(mainIndices.map { ordered[$0].startTs })
            func asleep(_ session: CachedSleepSession) -> Double {
                let duration = Double(max(0, session.endTs - session.effectiveStartTs)) / 60
                guard let raw = session.efficiency else { return duration }
                return duration * min(max(raw > 1 ? raw / 100 : raw, 0), 1)
            }
            result[pair.key] = ordered.reduce(into: (main: 0, naps: 0)) { totals, session in
                if mainStarts.contains(session.startTs) { totals.main += asleep(session) }
                else { totals.naps += asleep(session) }
            }
        }

        let dailyByDay = Dictionary(days.map { ($0.day, $0) }, uniquingKeysWith: { _, last in last })
        let dayKeys = Set(dailyByDay.keys).union(parts.keys).sorted()
        let all = dayKeys.map { dayKey in
            let day = dailyByDay[dayKey]
            let split = parts[dayKey]
            return SleepPlanningNightInput(
                day: dayKey, mainSleepMinutes: split?.main ?? day?.totalSleepMin,
                napSleepMinutes: split?.naps ?? 0, strain: day?.strain,
                efficiency: split != nil ? canonicalMainEfficiency(grouped[dayKey] ?? [],
                    habitualMidsleepSec: habitualMidsleepSec, timeZone: timeZone) : day?.efficiency,
                importedWhoopNeedMinutes: importedSleep[dayKey]?.needMin,
                importedWhoopDebtMinutes: importedSleep[dayKey]?.debtMin)
        }

        // Keep enough valid sleeps to establish the baseline for every contribution in the debt window,
        // plus all intervening missing days. Older repository depth cannot affect the result.
        var validSeen = 0
        var start = all.startIndex
        for index in all.indices.reversed() {
            if let sleep = all[index].mainSleepMinutes, sleep.isFinite, sleep > 0 { validSeen += 1 }
            start = index
            if validSeen >= SleepPlanningEngine.Configuration.maximumInputHistoryNights { break }
        }
        return Array(all[start...])
    }

    private static func canonicalMainEfficiency(_ sessions: [CachedSleepSession],
                                                habitualMidsleepSec: Int?,
                                                timeZone: TimeZone) -> Double? {
        guard !sessions.isEmpty else { return nil }
        let offset = sessions.map {
            timeZone.secondsFromGMT(for: Date(timeIntervalSince1970: TimeInterval($0.endTs)))
        }.max() ?? 0
        guard let indices = SleepStageTotals.mainNightGroupIndices(
            sessions.map { SleepStageTotals.NightBlock(start: $0.effectiveStartTs, end: $0.endTs) },
            offsetSec: offset, habitualMidsleepSec: habitualMidsleepSec) else { return nil }
        let group = indices.map { sessions[$0] }
        let inBed = group.reduce(0.0) { $0 + Double(max(0, $1.endTs - $1.effectiveStartTs)) }
            + SleepStageTotals.interFragmentAwakeSeconds(
                group.map { (start: $0.effectiveStartTs, end: $0.endTs) })
        guard inBed > 0 else { return nil }
        let asleep = group.reduce(0.0) { total, session in
            total + (SleepStageTotals.minutes(fromStagesJSON: session.stagesJSON)?.asleep ?? 0) * 60
        }
        return asleep > 0 ? asleep / inBed : nil
    }

    static func tonightNapMinutes(in inputs: [SleepPlanningNightInput], now: Date = Date()) -> Double {
        // Planning uses canonical local calendar wake-days, never Today's 04:00 presentation rollover.
        let today = Repository.localDayKey(now)
        return inputs.last(where: { $0.day == today })?.napSleepMinutes ?? 0
    }
}

extension Repository {
    func sleepPlanningResult(tonightStrain: Double? = nil) async -> SleepPlanningResult {
        let sessions = await allSleepSessions()
        let habitual = await habitualMidsleepSec()
        let inputs = SleepHistoryInputBuilder.build(days: days, sessions: sessions,
            habitualMidsleepSec: habitual, importedSleep: importedSleep)
        let tonightNaps = SleepHistoryInputBuilder.tonightNapMinutes(in: inputs)
        return SleepPlanningEngine.evaluate(inputs,
            tonightStrain: tonightStrain ?? days.last?.strain,
            tonightNapSleepMinutes: tonightNaps)
    }
}
