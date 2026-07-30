import XCTest
@testable import StrandAnalytics
import WhoopProtocol

final class WorkoutDetectorTests: XCTestCase {

    func testWhoop4RrContradictionRejectsFalseOpticalPlateau() throws {
        let start = 1_000
        let hr = (0..<365).map { HRSample(ts: start + $0, bpm: 158) }
        let gravity = (0..<365).map { i in
            GravitySample(ts: start + i, x: i.isMultiple(of: 2) ? 0.0 : 0.4, y: 0, z: 1)
        }
        let session = try XCTUnwrap(WorkoutDetector.detect(hr: hr, gravity: gravity, restingHR: 60).first)
        let contradicting = (0..<11).map { RRInterval(ts: start + $0 * 20, rrMs: 725) } // ~83 bpm

        XCTAssertTrue(WorkoutDetector.rrContradictsElevatedHR(session, hr: hr, rr: contradicting))
    }

    func testRrGateKeepsLegitimateHighHeartRateAndSparseEvidence() throws {
        let start = 2_000
        let hr = (0..<365).map { HRSample(ts: start + $0, bpm: 158) }
        let gravity = (0..<365).map { i in
            GravitySample(ts: start + i, x: i.isMultiple(of: 2) ? 0.0 : 0.4, y: 0, z: 1)
        }
        let session = try XCTUnwrap(WorkoutDetector.detect(hr: hr, gravity: gravity, restingHR: 60).first)
        let matching = (0..<11).map { RRInterval(ts: start + $0 * 20, rrMs: 380) } // ~158 bpm
        let sparseContradiction = (0..<7).map { RRInterval(ts: start + $0 * 20, rrMs: 725) }

        XCTAssertFalse(WorkoutDetector.rrContradictsElevatedHR(session, hr: hr, rr: matching))
        XCTAssertFalse(WorkoutDetector.rrContradictsElevatedHR(session, hr: hr, rr: sparseContradiction))
        XCTAssertFalse(WorkoutDetector.rrContradictsElevatedHR(session, hr: hr, rr: []))
    }

    func testRejectedBoutExpandsToWholeElevatedEpisodeButStopsAtRest() {
        let hr = (0..<120).map { HRSample(ts: $0, bpm: 65) }
            + (120..<900).map { HRSample(ts: $0, bpm: $0 < 500 || $0 > 520 ? 140 : 65) }
            + (900..<1_020).map { HRSample(ts: $0, bpm: 65) }
        let session = ExerciseSession(start: 400, end: 700, avgHR: 140, peakHR: 140, strain: nil,
                                      durationS: 300, zoneTimePct: [:], avgHRRPct: nil,
                                      hrmax: nil, hrmaxSource: "unknown", caloriesKcal: nil, caloriesKJ: nil)

        let span = WorkoutDetector.elevatedSpan(containing: session, hr: hr, restingHR: 60)
        XCTAssertEqual(span.start, 120)
        XCTAssertEqual(span.end, 899)
    }

    func testRejectedBoutEffortSpanDoesNotConsumeOrdinaryDrivingHeartRate() {
        let hr = (0..<120).map { HRSample(ts: $0, bpm: 85) }
            + (120..<600).map { HRSample(ts: $0, bpm: 145) }
            + (600..<900).map { HRSample(ts: $0, bpm: 85) }
        let session = ExerciseSession(start: 300, end: 700, avgHR: 140, peakHR: 145, strain: nil,
                                      durationS: 400, zoneTimePct: [:], avgHRRPct: nil,
                                      hrmax: nil, hrmaxSource: "unknown", caloriesKcal: nil, caloriesKJ: nil)

        let span = WorkoutDetector.elevatedSpan(containing: session, hr: hr, restingHR: 60)
        XCTAssertEqual(span.start, 120)
        XCTAssertEqual(span.end, 599)
    }

    func testEffortExclusionPreservesAdjacentLegitimateWorkout() {
        let rejected = [(start: 100, end: 500)]
        let legitimate = ExerciseSession(start: 450, end: 700, avgHR: 150, peakHR: 170, strain: nil,
                                         durationS: 250, zoneTimePct: [:], avgHRRPct: nil,
                                         hrmax: nil, hrmaxSource: "unknown", caloriesKcal: nil, caloriesKJ: nil)

        XCTAssertTrue(WorkoutDetector.excludesFromEffort(449, rejectedSpans: rejected,
                                                         retainedWorkouts: [legitimate]))
        XCTAssertFalse(WorkoutDetector.excludesFromEffort(450, rejectedSpans: rejected,
                                                          retainedWorkouts: [legitimate]))
        XCTAssertFalse(WorkoutDetector.excludesFromEffort(600, rejectedSpans: rejected,
                                                          retainedWorkouts: [legitimate]))
    }

    func testMultipleRejectedEffortEpisodesRemainIndependent() {
        let rejected = [(start: 100, end: 200), (start: 500, end: 600)]

        XCTAssertTrue(WorkoutDetector.excludesFromEffort(150, rejectedSpans: rejected, retainedWorkouts: []))
        XCTAssertFalse(WorkoutDetector.excludesFromEffort(350, rejectedSpans: rejected, retainedWorkouts: []))
        XCTAssertTrue(WorkoutDetector.excludesFromEffort(550, rejectedSpans: rejected, retainedWorkouts: []))
    }

    // MARK: - Activity series

    func testActivitySeriesFirstIsZero() {
        let grav = [
            GravitySample(ts: 0, x: 0, y: 0, z: 1),
            GravitySample(ts: 1, x: 0.3, y: 0, z: 1),  // Δ = 0.3
            GravitySample(ts: 2, x: 0.3, y: 0, z: 1),  // Δ = 0
        ]
        let series = WorkoutDetector.activitySeries(grav)
        XCTAssertEqual(series.count, 3)
        XCTAssertEqual(series[0].intensity, 0.0, accuracy: 1e-9)
        XCTAssertEqual(series[1].intensity, 0.3, accuracy: 1e-9)
        XCTAssertEqual(series[2].intensity, 0.0, accuracy: 1e-9)
    }

    func testActivitySeriesEmpty() {
        XCTAssertTrue(WorkoutDetector.activitySeries([]).isEmpty)
    }

    // MARK: - Calories

    func testCaloriesActiveAndRestingMale() {
        // 600 active samples at 150 bpm, male 80 kg 30 y, hrmax 190 → matches Python golden.
        let hr = (0..<600).map { HRSample(ts: $0, bpm: 150) }
        let profile = UserProfile(weightKg: 80, heightCm: 180, age: 30, sex: "male")
        let (kcal, kj) = Calories.estimateBoutCalories(hr, profile: profile, hrmax: 190, restingHR: 60)
        XCTAssertEqual(kcal, 146.972, accuracy: 0.1)
        XCTAssertEqual(kj, kcal * 4.184, accuracy: 1e-6)
    }

    func testCaloriesRestingBelowThreshold() {
        // HR below the 30% HRR active threshold → BMR rate (small per-sample).
        // Threshold = 60 + 0.30*(190-60) = 99. bpm 80 < 99 → resting.
        let hr = (0..<86400).map { HRSample(ts: $0, bpm: 80) }  // a full "day" of resting
        let profile = UserProfile(weightKg: 80, heightCm: 180, age: 30, sex: "male")
        let (kcal, _) = Calories.estimateBoutCalories(hr, profile: profile, hrmax: 190, restingHR: 60)
        // 86400 s at BMR rate ≈ full BMR ≈ 1853.6 kcal/day.
        XCTAssertEqual(kcal, 1853.632, accuracy: 1.0)
    }

    func testCaloriesSexCoefficientsDiffer() {
        let hr = (0..<600).map { HRSample(ts: $0, bpm: 150) }
        let male = Calories.estimateBoutCalories(
            hr, profile: UserProfile(weightKg: 70, heightCm: 175, age: 30, sex: "male"),
            hrmax: 190, restingHR: 60).0
        let female = Calories.estimateBoutCalories(
            hr, profile: UserProfile(weightKg: 70, heightCm: 175, age: 30, sex: "female"),
            hrmax: 190, restingHR: 60).0
        XCTAssertNotEqual(male, female, accuracy: 0.0)
    }

    // MARK: - Detection

    /// A workout: high HR + sustained motion for `durationS`, embedded in a rest day.
    private func workoutDay(workoutStart: Int, workoutDur: Int) -> (hr: [HRSample], grav: [GravitySample]) {
        var hr: [HRSample] = []
        var grav: [GravitySample] = []
        let dayStart = workoutStart - 30 * 60
        let dayEnd = workoutStart + workoutDur + 30 * 60
        for t in dayStart..<dayEnd {
            let inWorkout = t >= workoutStart && t < workoutStart + workoutDur
            // Resting periods: HR 55, still gravity. Workout: HR 165, moving gravity.
            hr.append(HRSample(ts: t, bpm: inWorkout ? 165 : 55))
            if inWorkout {
                let phase = Double((t - workoutStart) % 2) * 0.5  // 0.5 g oscillation → moving
                grav.append(GravitySample(ts: t, x: phase, y: 0, z: 1))
            } else {
                grav.append(GravitySample(ts: t, x: 0, y: 0, z: 1))  // still
            }
        }
        return (hr, grav)
    }

    func testDetectFindsWorkout() {
        let start = 5_000_000
        let dur = 20 * 60  // 20 min
        let (hr, grav) = workoutDay(workoutStart: start, workoutDur: dur)
        let sessions = WorkoutDetector.detect(hr: hr, gravity: grav, age: 30)
        XCTAssertEqual(sessions.count, 1)
        let w = sessions[0]
        XCTAssertEqual(w.avgHR, 165, accuracy: 1.0)
        XCTAssertEqual(w.peakHR, 165)
        XCTAssertGreaterThan(w.durationS, Double(15 * 60))
        // Zone breakdown sums to ~100.
        let total = w.zoneTimePct.values.reduce(0, +)
        XCTAssertEqual(total, 100.0, accuracy: 0.5)
        XCTAssertEqual(w.hrmaxSource, "tanaka")  // age supplied, thin observed history
    }

    func testDetectWithProfileEstimatesCalories() {
        let start = 6_000_000
        let dur = 20 * 60
        let (hr, grav) = workoutDay(workoutStart: start, workoutDur: dur)
        let profile = UserProfile(weightKg: 80, heightCm: 180, age: 30, sex: "male")
        let sessions = WorkoutDetector.detect(hr: hr, gravity: grav, age: 30, profile: profile)
        XCTAssertEqual(sessions.count, 1)
        XCTAssertNotNil(sessions[0].caloriesKcal)
        XCTAssertGreaterThan(sessions[0].caloriesKcal!, 0)
    }

    func testDetectRejectsShortBout() {
        let start = 7_000_000
        let (hr, grav) = workoutDay(workoutStart: start, workoutDur: 3 * 60)  // 3 min < 5
        XCTAssertTrue(WorkoutDetector.detect(hr: hr, gravity: grav, age: 30).isEmpty)
    }

    func testDetectEmptyStreams() {
        XCTAssertTrue(WorkoutDetector.detect(hr: [], gravity: [], age: 30).isEmpty)
        let grav = [GravitySample(ts: 0, x: 0, y: 0, z: 1)]
        XCTAssertTrue(WorkoutDetector.detect(hr: [], gravity: grav, age: 30).isEmpty)
    }

    func testDetectRejectsLowIntensityBlip() {
        // Moving + slightly elevated HR but dominated by zone 0/1 (HR just over floor).
        // resting derived ~55, floor = 70. HR 75 is above floor but at ~15% HRR (zone 0).
        let start = 8_000_000
        let dur = 20 * 60
        var hr: [HRSample] = []
        var grav: [GravitySample] = []
        let dayStart = start - 30 * 60
        let dayEnd = start + dur + 30 * 60
        for t in dayStart..<dayEnd {
            let inBout = t >= start && t < start + dur
            hr.append(HRSample(ts: t, bpm: inBout ? 75 : 55))
            if inBout {
                let phase = Double((t - start) % 2) * 0.5
                grav.append(GravitySample(ts: t, x: phase, y: 0, z: 1))
            } else {
                grav.append(GravitySample(ts: t, x: 0, y: 0, z: 1))
            }
        }
        // age 30 → hrmax 187, zone math available → z2+ fraction ≈ 0 < 0.50 → rejected.
        XCTAssertTrue(WorkoutDetector.detect(hr: hr, gravity: grav, age: 30).isEmpty)
    }

    // MARK: - Sustained-effort fragmentation (#303)

    /// A long endurance bout (e.g. a road bike ride) that dips momentarily every few
    /// minutes — coasting downhill, a junction, a brief sensor gap — so that motion
    /// falls below threshold for a `dipS`-long stretch on a `cadenceS` cadence. HR
    /// stays elevated throughout (you don't actually rest). Helper returns a full day
    /// with the ride embedded in rest, plus the true ride span for assertions.
    private func longRideWithDips(
        rideStart: Int, rideDur: Int, cadenceS: Int, dipS: Int
    ) -> (hr: [HRSample], grav: [GravitySample]) {
        var hr: [HRSample] = []
        var grav: [GravitySample] = []
        let dayStart = rideStart - 30 * 60
        let dayEnd = rideStart + rideDur + 30 * 60
        for t in dayStart..<dayEnd {
            let inRide = t >= rideStart && t < rideStart + rideDur
            // Coasting dip: the last `dipS` seconds of every `cadenceS`-second cycle.
            let phaseInCycle = (t - rideStart) % cadenceS
            let coasting = inRide && phaseInCycle >= cadenceS - dipS
            // HR stays high the whole ride (a real dip in cadence ≠ a dip in HR).
            hr.append(HRSample(ts: t, bpm: inRide ? 150 : 52))
            if inRide && !coasting {
                let osc = Double((t - rideStart) % 2) * 0.5  // pedalling → moving
                grav.append(GravitySample(ts: t, x: osc, y: 0, z: 1))
            } else {
                grav.append(GravitySample(ts: t, x: 0, y: 0, z: 1))  // still / coasting
            }
        }
        return (hr, grav)
    }

    func testLongRideWithBriefDipsIsOneWorkout() {
        // ~4 h ride (matches the issue: 13:00–16:52) with a ~2-min coasting dip every
        // ~8 min. Each dip exceeds the OLD 150 s merge gap, so it used to shatter the
        // ride into ~30 sub-5-min slivers, most of which were then dropped by the
        // minimum-duration filter — surfacing as a handful of tiny "workouts".
        let start = 9_000_000
        let rideDur = 232 * 60      // 3 h 52 m
        let (hr, grav) = longRideWithDips(
            rideStart: start, rideDur: rideDur, cadenceS: 8 * 60, dipS: 180)
        let sessions = WorkoutDetector.detect(hr: hr, gravity: grav, age: 30)

        // One ride → one workout, spanning ~the whole ride (not a pile of fragments).
        XCTAssertEqual(sessions.count, 1, "sustained ride fragmented into \(sessions.count) workouts")
        let w = sessions[0]
        XCTAssertGreaterThan(w.durationS, Double(rideDur) * 0.9,
                             "merged ride too short: \(Int(w.durationS))s of \(rideDur)s")
        XCTAssertEqual(w.avgHR, 150, accuracy: 2.0)
    }

    func testGenuinelySeparateWorkoutsStaySeparate() {
        // Two real workouts separated by a long genuine rest (HR drops to resting and
        // motion stops for ~25 min) must NOT be merged by the bridge. Guards against
        // the fix over-merging unrelated sessions.
        let startA = 10_000_000
        let durA = 20 * 60
        let restGap = 25 * 60               // 25 min true rest, well beyond the bridge
        let startB = startA + durA + restGap
        let durB = 20 * 60
        var hr: [HRSample] = []
        var grav: [GravitySample] = []
        let dayStart = startA - 30 * 60
        let dayEnd = startB + durB + 30 * 60
        for t in dayStart..<dayEnd {
            let inA = t >= startA && t < startA + durA
            let inB = t >= startB && t < startB + durB
            let active = inA || inB
            hr.append(HRSample(ts: t, bpm: active ? 160 : 52))
            if active {
                let osc = Double(t % 2) * 0.5
                grav.append(GravitySample(ts: t, x: osc, y: 0, z: 1))
            } else {
                grav.append(GravitySample(ts: t, x: 0, y: 0, z: 1))
            }
        }
        let sessions = WorkoutDetector.detect(hr: hr, gravity: grav, age: 30)
        XCTAssertEqual(sessions.count, 2, "separate workouts were over-merged")
    }
}
