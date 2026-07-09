import Foundation

public struct CloudReadRequest: Equatable, Sendable {
    public var sourceDeviceIds: [String]
    public var windowDays: Int
    public var metricSeriesKeys: [String]
    public var fromDay: String?
    public var toDay: String?
    public var fromTs: Int?
    public var toTs: Int?

    public init(
        sourceDeviceIds: [String] = ["my-whoop", "my-whoop-noop"],
        windowDays: Int = 30,
        metricSeriesKeys: [String] = [],
        fromDay: String? = nil,
        toDay: String? = nil,
        fromTs: Int? = nil,
        toTs: Int? = nil
    ) {
        self.sourceDeviceIds = sourceDeviceIds
        self.windowDays = windowDays
        self.metricSeriesKeys = metricSeriesKeys
        self.fromDay = fromDay
        self.toDay = toDay
        self.fromTs = fromTs
        self.toTs = toTs
    }
}

public struct CloudReadSnapshot: Equatable, Sendable {
    public var sources: [CloudSourceDescriptorDTO]
    public var dailyMetrics: [DailyMetricDTO]
    public var sleepSessions: [SleepSessionDTO]
    public var workouts: [WorkoutDTO]
    public var metricSeries: [MetricSeriesPointDTO]

    public init(
        sources: [CloudSourceDescriptorDTO] = [],
        dailyMetrics: [DailyMetricDTO] = [],
        sleepSessions: [SleepSessionDTO] = [],
        workouts: [WorkoutDTO] = [],
        metricSeries: [MetricSeriesPointDTO] = []
    ) {
        self.sources = sources
        self.dailyMetrics = dailyMetrics
        self.sleepSessions = sleepSessions
        self.workouts = workouts
        self.metricSeries = metricSeries
    }
}

public protocol LocalReadAdapter: Sendable {
    func readSnapshot(_ request: CloudReadRequest) async throws -> CloudReadSnapshot
}

/// Default adapter used by the app hook. It keeps Cloud inert unless an explicit read-only adapter is
/// installed by a debug command or a later opt-in flow.
public struct EmptyLocalReadAdapter: LocalReadAdapter {
    public init() {}

    public func readSnapshot(_ request: CloudReadRequest) async throws -> CloudReadSnapshot {
        _ = request
        return CloudReadSnapshot()
    }
}
