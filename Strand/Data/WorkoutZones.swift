import Foundation
import WhoopStore
import WhoopProtocol
import StrandAnalytics

// MARK: - Imported per-workout HR zones
//
// `zonesJSON` is the verbatim HR-zone-percentage object from the WHOOP CSV import
// (WhoopImporter writes "z1"…"z5"; the Android importer writes "zone1"…"zone5" for the
// same data — tolerate both so a cache moved between platforms still renders). Values
// are 0–100 percent of the workout's duration and may sum to less than 100 (time below
// zone 1 is not exported).
enum WorkoutZones {

    private static func object(_ zonesJSON: String?) -> [String: Any]? {
        guard let zonesJSON, let data = zonesJSON.data(using: .utf8) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    /// Z1…Z5 percentages (0–100) for one workout, or nil when the row carries no usable zone data.
    static func percents(_ zonesJSON: String?) -> [Double]? {
        guard let obj = object(zonesJSON) else { return nil }
        let p = (1...5).map { i -> Double in
            let v = (obj["z\(i)"] ?? obj["zone\(i)"]) as? NSNumber
            return min(max(v?.doubleValue ?? 0, 0), 100)
        }
        return p.contains(where: { $0 > 0 }) ? p : nil
    }

    static func derivedJSON(samples: [HRSample], hrMax: Double) -> String? {
        guard samples.count > 1, hrMax > 0 else { return nil }
        let sorted = samples.sorted { $0.ts < $1.ts }
        let zones = HRZones.zones(maxHR: hrMax)
        var seconds = [Double](repeating: 0, count: 6)
        for i in 0..<(sorted.count - 1) {
            let delta = sorted[i + 1].ts - sorted[i].ts
            guard delta > 0, delta <= 15 else { continue }
            let zone = zones.zoneNumber(forBPM: Double(sorted[i].bpm))
            seconds[max(0, min(5, zone))] += Double(delta)
        }
        let total = seconds.reduce(0, +)
        guard total > 0 else { return nil }
        let values = Dictionary(uniqueKeysWithValues: (0...5).map { ("z\($0)", seconds[$0] / total * 100) })
        guard let data = try? JSONSerialization.data(withJSONObject: values, options: [.sortedKeys]) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// Duration-weighted zone minutes across rows. Mirrors the daily-metric derivation in
    /// WhoopImporter (duration-minutes × pct ÷ 100). APPROXIMATE: an on-device aggregate of
    /// the imported per-workout percentages, not a WHOOP-computed figure.
    struct Summary {
        let minutes: [Double]          // index 0 = below Z1 (Z0), then Z1 … Z5
        let sessionsWithZones: Int
        var totalMinutes: Double { minutes.reduce(0, +) }
    }

    static func summary(from rows: [WorkoutRow]) -> Summary? {
        var mins = [Double](repeating: 0, count: 6)
        var n = 0
        for r in rows {
            guard let p = percents(r.zonesJSON) else { continue }
            let durMin = (r.durationS ?? Double(r.endTs - r.startTs)) / 60.0
            guard durMin > 0 else { continue }
            let recordedPct = min(100, p.reduce(0, +))
            let explicitZ0 = (object(r.zonesJSON)?["z0"] as? NSNumber)?.doubleValue
            mins[0] += durMin * min(max(explicitZ0 ?? (100 - recordedPct), 0), 100) / 100.0
            for i in 0..<5 { mins[i + 1] += durMin * p[i] / 100.0 }
            n += 1
        }
        guard n > 0, mins.reduce(0, +) > 0 else { return nil }
        return Summary(minutes: mins, sessionsWithZones: n)
    }
}
