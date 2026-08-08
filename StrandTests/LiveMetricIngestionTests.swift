import Combine
import XCTest
#if NOOP_IOS_TEST_HOST
@testable import NOOP_Staging
#else
@testable import Strand
#endif

#if DEBUG
/// Pins the logical-update boundary between independently published live fields and AppModel's metric
/// pipeline. A BLE packet may still publish both HR and R-R for their dedicated consumers, but its
/// smoothing/workout/stress work must happen once.
@MainActor
final class LiveMetricIngestionTests: XCTestCase {
    private var savedWorkout: ActiveWorkoutPersistence.Snapshot?

    override func setUp() {
        super.setUp()
        savedWorkout = ActiveWorkoutPersistence.load()
        ActiveWorkoutPersistence.clear()
    }

    override func tearDown() {
        ActiveWorkoutPersistence.clear()
        if let savedWorkout { ActiveWorkoutPersistence.store(savedWorkout) }
        savedWorkout = nil
        super.tearDown()
    }

    func testPairedHRAndRRUpdateRunsMetricPipelineOnceAndPreservesFieldPublishers() {
        let model = AppModel()
        var hrPublications = 0
        var rrPublications = 0
        var cancellables = Set<AnyCancellable>()
        model.live.$heartRate.dropFirst().sink { _ in hrPublications += 1 }.store(in: &cancellables)
        model.live.$rr.dropFirst().sink { _ in rrPublications += 1 }.store(in: &cancellables)
        model.resetLiveMetricDebugCounts()

        StandardHRSource.publishMeasurement(hr: 120, rr: [500, 510], to: model.live)

        XCTAssertEqual(model.liveMetricIngestionCount, 1, "one physical packet must ingest once")
        XCTAssertEqual(model.liveMetricWorkoutCaptureCount, 1)
        XCTAssertEqual(model.liveMetricStressEvaluationCount, 1)
        XCTAssertEqual(hrPublications, 1, "HR consumers still receive their normal publication")
        XCTAssertEqual(rrPublications, 1, "R-R/HRV consumers still receive their normal publication")
        XCTAssertEqual(model.bpm, 120)
        XCTAssertEqual(model.live.rr, [500, 510])
        XCTAssertEqual(model.live.rrRecent, [500, 510])
    }

    func testHROnlyUpdateRunsMetricPipelineOnce() {
        let model = AppModel()
        model.resetLiveMetricDebugCounts()

        StandardHRSource.publishMeasurement(hr: 96, rr: [], to: model.live)

        XCTAssertEqual(model.liveMetricIngestionCount, 1)
        XCTAssertEqual(model.liveMetricWorkoutCaptureCount, 1)
        XCTAssertEqual(model.liveMetricStressEvaluationCount, 1)
        XCTAssertEqual(model.bpm, 96)
        XCTAssertTrue(model.live.rr.isEmpty)
    }

    func testRROnlyUpdateRunsOnceAndStillProvidesHRFallback() {
        let model = AppModel()
        model.resetLiveMetricDebugCounts()

        model.live.updateRRIntervals([800])

        XCTAssertEqual(model.liveMetricIngestionCount, 1)
        XCTAssertEqual(model.liveMetricWorkoutCaptureCount, 1)
        XCTAssertEqual(model.liveMetricStressEvaluationCount, 1)
        XCTAssertEqual(model.bpm, 75, "R-R-only sources retain the 60,000 / interval HR fallback")
        XCTAssertEqual(model.live.rr, [800])
        XCTAssertEqual(model.live.rrRecent, [800])
    }

    func testPairedPacketAddsOneActiveWorkoutSample() {
        let model = AppModel()
        model.activeWorkout = AppModel.ActiveWorkout(start: Date(), sport: "Test")
        model.resetLiveMetricDebugCounts()

        StandardHRSource.publishMeasurement(hr: 135, rr: [444], to: model.live)

        XCTAssertEqual(model.liveMetricIngestionCount, 1)
        XCTAssertEqual(model.liveMetricWorkoutCaptureCount, 1)
        XCTAssertEqual(model.liveMetricStressEvaluationCount, 1)
        XCTAssertEqual(model.activeWorkout?.samples.count, 1,
                       "one paired packet must not append duplicate workout samples")
        XCTAssertEqual(model.activeWorkout?.samples.first?.bpm, 135)
    }

    func testWhoopRRThenHROrderingCommitsOneMetricUpdate() {
        let model = AppModel()
        var publicationOrder: [String] = []
        var cancellables = Set<AnyCancellable>()
        model.live.$rr.dropFirst().sink { _ in publicationOrder.append("rr") }.store(in: &cancellables)
        model.live.$heartRate.dropFirst().sink { _ in publicationOrder.append("hr") }.store(in: &cancellables)
        model.resetLiveMetricDebugCounts()

        // BLEManager.parseStandardHR intentionally keeps this WHOOP path's established R-R-first order.
        model.live.performBiometricUpdate {
            model.live.setRRIntervals([600])
            model.live.heartRate = 100
        }

        XCTAssertEqual(publicationOrder, ["rr", "hr"])
        XCTAssertEqual(model.liveMetricIngestionCount, 1)
        XCTAssertEqual(model.bpm, 100)
        XCTAssertEqual(model.live.rr, [600])
    }

    func testMarkConnectedDoesNotRepublishUnchangedTrue() {
        let live = LiveState()
        var publications = 0
        let cancellable = live.$connected.dropFirst().sink { _ in publications += 1 }

        StandardHRSource.publishMeasurement(hr: 80, rr: [], to: live)
        StandardHRSource.publishMeasurement(hr: 81, rr: [], to: live)

        XCTAssertEqual(publications, 1)
        withExtendedLifetime(cancellable) {}
    }
}
#endif
