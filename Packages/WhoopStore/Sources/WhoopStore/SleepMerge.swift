import Foundation

/// Merge imported and on-device-computed sleep sessions for display and export.
public enum SleepMerge {
    /// Merge imported + computed sleep, preserving EVERY session.
    ///
    /// A day with two sessions (e.g. a main night and an afternoon nap, or two nights ending the same
    /// local day) must keep BOTH — the previous per-day dictionary overwrote on collision and silently
    /// dropped one (#715). Imported sessions take precedence per day: if any imported session ends on a
    /// given local day, the computed sessions for that day yield to it (the existing imported-over-computed
    /// rule); on days with no imported session the computed sessions stand. Result is sorted by start time.
    ///
    /// - Parameter endDay: maps a session to its canonical LOCAL end-day key (callers inject their
    ///   timezone-aware keyer so this stays pure and testable).
    public static func merge(imported: [CachedSleepSession],
                             computed: [CachedSleepSession],
                             endDay: (CachedSleepSession) -> String) -> [CachedSleepSession] {
        var importedByDay: [String: [CachedSleepSession]] = [:]
        for session in imported { importedByDay[endDay(session), default: []].append(session) }
        var computedByDay: [String: [CachedSleepSession]] = [:]
        for session in computed { computedByDay[endDay(session), default: []].append(session) }

        var out: [CachedSleepSession] = []
        out.reserveCapacity(imported.count + computed.count)
        for (day, importedSessions) in importedByDay {
            if let computedSessions = computedByDay[day],
               !importedSessions.contains(where: hasStages),
               computedSessions.contains(where: hasStages) {
                out.append(contentsOf: computedSessions)
            } else {
                out.append(contentsOf: importedSessions)
            }
        }
        for (day, computedSessions) in computedByDay where importedByDay[day] == nil {
            out.append(contentsOf: computedSessions)
        }
        return out.sorted { $0.startTs < $1.startTs }
    }

    static func hasStages(_ session: CachedSleepSession) -> Bool {
        guard let stages = session.stagesJSON?.trimmingCharacters(in: .whitespacesAndNewlines) else {
            return false
        }
        return !stages.isEmpty && stages != "[]"
    }
}
