import Foundation

public struct CloudSnapshotSummary: Codable, Equatable, Sendable {
    public var window: CloudSyncWindowDTO
    public var sourceDeviceIds: [String]
    public var dailyMetricCount: Int
    public var sleepSessionCount: Int
    public var workoutCount: Int
    public var metricSeriesCount: Int
    public var countsBySource: [String: SourceCounts]
    public var metricSeriesKeysBySource: [String: [String]]
    public var containsSleepDebtMetric: Bool
    public var maxDailyEffort: Double?
    public var maxWorkoutEffort: Double?

    public init(
        window: CloudSyncWindowDTO = CloudSyncWindowDTO(),
        sourceDeviceIds: [String] = [],
        dailyMetricCount: Int = 0,
        sleepSessionCount: Int = 0,
        workoutCount: Int = 0,
        metricSeriesCount: Int = 0,
        countsBySource: [String: SourceCounts] = [:],
        metricSeriesKeysBySource: [String: [String]] = [:],
        containsSleepDebtMetric: Bool = false,
        maxDailyEffort: Double? = nil,
        maxWorkoutEffort: Double? = nil
    ) {
        self.window = window
        self.sourceDeviceIds = sourceDeviceIds
        self.dailyMetricCount = dailyMetricCount
        self.sleepSessionCount = sleepSessionCount
        self.workoutCount = workoutCount
        self.metricSeriesCount = metricSeriesCount
        self.countsBySource = countsBySource
        self.metricSeriesKeysBySource = metricSeriesKeysBySource
        self.containsSleepDebtMetric = containsSleepDebtMetric
        self.maxDailyEffort = maxDailyEffort
        self.maxWorkoutEffort = maxWorkoutEffort
    }

    public struct SourceCounts: Codable, Equatable, Sendable {
        public var dailyMetrics: Int
        public var sleepSessions: Int
        public var workouts: Int
        public var metricSeries: Int

        public init(dailyMetrics: Int = 0, sleepSessions: Int = 0, workouts: Int = 0, metricSeries: Int = 0) {
            self.dailyMetrics = dailyMetrics
            self.sleepSessions = sleepSessions
            self.workouts = workouts
            self.metricSeries = metricSeries
        }
    }

    public static func make(from snapshot: CloudReadSnapshot, request: CloudReadRequest) -> CloudSnapshotSummary {
        var countsBySource: [String: SourceCounts] = [:]

        for item in snapshot.dailyMetrics {
            countsBySource[item.sourceDeviceId, default: SourceCounts()].dailyMetrics += 1
        }
        for item in snapshot.sleepSessions {
            countsBySource[item.sourceDeviceId, default: SourceCounts()].sleepSessions += 1
        }
        for item in snapshot.workouts {
            countsBySource[item.sourceDeviceId, default: SourceCounts()].workouts += 1
        }
        for item in snapshot.metricSeries {
            countsBySource[item.sourceDeviceId, default: SourceCounts()].metricSeries += 1
        }

        var keysBySource: [String: Set<String>] = [:]
        for point in snapshot.metricSeries {
            keysBySource[point.sourceDeviceId, default: []].insert(point.key)
        }

        let sortedKeysBySource = keysBySource.mapValues { Array($0).sorted() }
        let allKeys = Set(snapshot.metricSeries.map(\.key))

        return CloudSnapshotSummary(
            window: CloudSyncWindowDTO(
                fromDay: request.fromDay,
                toDay: request.toDay,
                fromTs: request.fromTs,
                toTs: request.toTs
            ),
            sourceDeviceIds: snapshot.sources.map(\.sourceDeviceId).sorted(),
            dailyMetricCount: snapshot.dailyMetrics.count,
            sleepSessionCount: snapshot.sleepSessions.count,
            workoutCount: snapshot.workouts.count,
            metricSeriesCount: snapshot.metricSeries.count,
            countsBySource: countsBySource,
            metricSeriesKeysBySource: sortedKeysBySource,
            containsSleepDebtMetric: allKeys.contains("sleep_debt_min"),
            maxDailyEffort: snapshot.dailyMetrics.compactMap(\.effort).max(),
            maxWorkoutEffort: snapshot.workouts.compactMap(\.effort).max()
        )
    }
}

public enum CloudSnapshotSerializer {
    public static func prettyJSON<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(value)
    }
}
