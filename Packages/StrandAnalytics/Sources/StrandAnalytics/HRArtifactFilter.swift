import Foundation
import WhoopProtocol

/// Conservative artifact rejection for HR-derived metabolic metrics.
///
/// Raw samples remain untouched in the store. This filter removes only short, large, positive
/// excursions that are bracketed by a lower local baseline on both sides. Gradual changes,
/// unbracketed changes, and elevated runs lasting longer than `maxExcursionSeconds` pass through.
public enum HRArtifactFilter {
    /// A real heart cannot rise and recover by this much in only a few seconds. Kept deliberately
    /// high so ordinary HR noise and interval-workout transitions are not treated as artifacts.
    public static let jumpBPM = 45
    /// Once an excursion starts, tolerate some optical wobble without splitting the island.
    public static let elevatedBPM = 35
    /// The post-excursion reading must return close to the pre-excursion baseline.
    public static let returnToleranceBPM = 20
    /// Maximum timestamp span of an implausibly short elevated island.
    public static let maxExcursionSeconds = 12
    /// Look far enough around sparse (~30 s) streams to validate a single reading, but do not
    /// compare unrelated portions of the day.
    public static let bracketWindowSeconds = 90

    public static func filteringShortSpikes(_ samples: [HRSample]) -> [HRSample] {
        guard samples.count >= 3 else { return samples }

        // Metric callers normally receive ordered, unique store rows. Normalize defensively so
        // imported/pure-function inputs cannot turn out-of-order timestamps into false islands.
        let alreadyOrdered = zip(samples, samples.dropFirst()).allSatisfy { pair in
            pair.0.ts <= pair.1.ts
        }
        let ordered = alreadyOrdered ? samples : samples.enumerated()
            .sorted { ($0.element.ts, $0.offset) < ($1.element.ts, $1.offset) }
            .map(\.element)
        var filtered = ordered
        var i = 1

        while i < ordered.count - 1 {
            // Cheap hot-path gate: almost every ordinary reading exits here. Build/sort the local
            // median window only at an abrupt positive boundary.
            guard ordered[i].bpm - ordered[i - 1].bpm >= jumpBPM else {
                i += 1
                continue
            }
            let prior = localMedian(ordered, endingBefore: i, seconds: bracketWindowSeconds)
            // Only begin at a real low→high boundary. Without this gate, the last few seconds of a
            // long legitimate interval could look like a short island when its eventual recovery
            // enters the look-ahead window.
            guard let baseline = prior,
                  abs(ordered[i - 1].bpm - baseline) <= returnToleranceBPM,
                  ordered[i].bpm >= baseline + jumpBPM else {
                i += 1
                continue
            }

            var end = i
            while end + 1 < ordered.count,
                  ordered[end + 1].ts - ordered[i].ts <= maxExcursionSeconds,
                  ordered[end + 1].bpm >= baseline + elevatedBPM {
                end += 1
            }

            let next = end + 1
            let hasTimelyReturn = next < ordered.count
                && ordered[next].ts - ordered[end].ts <= bracketWindowSeconds
                && abs(ordered[next].bpm - baseline) <= returnToleranceBPM
            let short = ordered[end].ts - ordered[i].ts <= maxExcursionSeconds

            if short && hasTimelyReturn {
                // Preserve timestamps/coverage: deleting a sample would make the preceding reading
                // inherit a larger duration and can move a just-qualified stream below its sample gate.
                // Replace only in this ephemeral metric stream; the durable raw bpm remains untouched.
                for index in i...end {
                    filtered[index] = HRSample(ts: ordered[index].ts, bpm: baseline)
                }
                i = next
            } else {
                i += 1
            }
        }

        return filtered
    }

    private static func localMedian(_ samples: [HRSample], endingBefore index: Int,
                                    seconds: Int) -> Int? {
        let cutoff = samples[index].ts - seconds
        var values: [Int] = []
        var j = index - 1
        while j >= 0, samples[j].ts >= cutoff {
            values.append(samples[j].bpm)
            j -= 1
        }
        guard !values.isEmpty else { return nil }
        values.sort()
        let middle = values.count / 2
        if values.count.isMultiple(of: 2) {
            return (values[middle - 1] + values[middle]) / 2
        }
        return values[middle]
    }
}
