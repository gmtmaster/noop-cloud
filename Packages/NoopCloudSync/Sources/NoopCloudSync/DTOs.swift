import Foundation

public struct CloudSourceDescriptorDTO: Codable, Equatable, Sendable {
    public var sourceDeviceId: String
    public var kind: String

    public init(sourceDeviceId: String, kind: String) {
        self.sourceDeviceId = sourceDeviceId
        self.kind = kind
    }
}

public struct CloudSyncWindowDTO: Codable, Equatable, Sendable {
    public var fromDay: String?
    public var toDay: String?
    public var fromTs: Int?
    public var toTs: Int?

    public init(fromDay: String? = nil, toDay: String? = nil, fromTs: Int? = nil, toTs: Int? = nil) {
        self.fromDay = fromDay
        self.toDay = toDay
        self.fromTs = fromTs
        self.toTs = toTs
    }
}

public struct DailyMetricDTO: Codable, Equatable, Sendable {
    public var sourceDeviceId: String
    public var day: String
    public var totalSleepMin: Double?
    public var efficiency: Double?
    public var deepMin: Double?
    public var remMin: Double?
    public var lightMin: Double?
    public var disturbances: Int?
    public var restingHr: Int?
    public var avgHrv: Double?
    public var recovery: Double?
    public var effort: Double?
    public var exerciseCount: Int?
    public var spo2Pct: Double?
    public var skinTempDevC: Double?
    public var respRateBpm: Double?
    public var steps: Int?
    public var activeKcalEst: Double?

    public init(
        sourceDeviceId: String,
        day: String,
        totalSleepMin: Double? = nil,
        efficiency: Double? = nil,
        deepMin: Double? = nil,
        remMin: Double? = nil,
        lightMin: Double? = nil,
        disturbances: Int? = nil,
        restingHr: Int? = nil,
        avgHrv: Double? = nil,
        recovery: Double? = nil,
        effort: Double? = nil,
        exerciseCount: Int? = nil,
        spo2Pct: Double? = nil,
        skinTempDevC: Double? = nil,
        respRateBpm: Double? = nil,
        steps: Int? = nil,
        activeKcalEst: Double? = nil
    ) {
        self.sourceDeviceId = sourceDeviceId
        self.day = day
        self.totalSleepMin = totalSleepMin
        self.efficiency = efficiency
        self.deepMin = deepMin
        self.remMin = remMin
        self.lightMin = lightMin
        self.disturbances = disturbances
        self.restingHr = restingHr
        self.avgHrv = avgHrv
        self.recovery = recovery
        self.effort = effort
        self.exerciseCount = exerciseCount
        self.spo2Pct = spo2Pct
        self.skinTempDevC = skinTempDevC
        self.respRateBpm = respRateBpm
        self.steps = steps
        self.activeKcalEst = activeKcalEst
    }
}

public struct SleepSessionDTO: Codable, Equatable, Sendable {
    public var sourceDeviceId: String
    public var startTs: Int
    public var endTs: Int
    public var efficiency: Double?
    public var restingHr: Int?
    public var avgHrv: Double?
    public var stagesJSON: String?
    public var userEdited: Bool?
    public var startTsAdjusted: Int?

    public init(
        sourceDeviceId: String,
        startTs: Int,
        endTs: Int,
        efficiency: Double? = nil,
        restingHr: Int? = nil,
        avgHrv: Double? = nil,
        stagesJSON: String? = nil,
        userEdited: Bool? = nil,
        startTsAdjusted: Int? = nil
    ) {
        self.sourceDeviceId = sourceDeviceId
        self.startTs = startTs
        self.endTs = endTs
        self.efficiency = efficiency
        self.restingHr = restingHr
        self.avgHrv = avgHrv
        self.stagesJSON = stagesJSON
        self.userEdited = userEdited
        self.startTsAdjusted = startTsAdjusted
    }
}

public struct WorkoutDTO: Codable, Equatable, Sendable {
    public var sourceDeviceId: String
    public var startTs: Int
    public var endTs: Int
    public var sport: String
    public var source: String
    public var durationS: Double?
    public var energyKcal: Double?
    public var avgHr: Int?
    public var maxHr: Int?
    public var effort: Double?
    public var distanceM: Double?
    public var zonesJSON: String?

    public init(
        sourceDeviceId: String,
        startTs: Int,
        endTs: Int,
        sport: String,
        source: String,
        durationS: Double? = nil,
        energyKcal: Double? = nil,
        avgHr: Int? = nil,
        maxHr: Int? = nil,
        effort: Double? = nil,
        distanceM: Double? = nil,
        zonesJSON: String? = nil
    ) {
        self.sourceDeviceId = sourceDeviceId
        self.startTs = startTs
        self.endTs = endTs
        self.sport = sport
        self.source = source
        self.durationS = durationS
        self.energyKcal = energyKcal
        self.avgHr = avgHr
        self.maxHr = maxHr
        self.effort = effort
        self.distanceM = distanceM
        self.zonesJSON = zonesJSON
    }
}

public struct MetricSeriesPointDTO: Codable, Equatable, Sendable {
    public var sourceDeviceId: String
    public var day: String
    public var key: String
    public var value: Double

    public init(sourceDeviceId: String, day: String, key: String, value: Double) {
        self.sourceDeviceId = sourceDeviceId
        self.day = day
        self.key = key
        self.value = value
    }
}

public struct CloudSyncBatchDTO: Codable, Equatable, Sendable {
    public var clientBatchId: String
    public var schemaVersion: String
    public var appVersion: String?
    public var sourceDeviceIds: [String]
    public var window: CloudSyncWindowDTO
    public var sources: [CloudSourceDescriptorDTO]
    public var dailyMetrics: [DailyMetricDTO]
    public var sleepSessions: [SleepSessionDTO]
    public var workouts: [WorkoutDTO]
    public var metricSeries: [MetricSeriesPointDTO]

    public init(
        clientBatchId: String = UUID().uuidString,
        schemaVersion: String,
        appVersion: String? = nil,
        sourceDeviceIds: [String]? = nil,
        window: CloudSyncWindowDTO = CloudSyncWindowDTO(),
        sources: [CloudSourceDescriptorDTO] = [],
        dailyMetrics: [DailyMetricDTO] = [],
        sleepSessions: [SleepSessionDTO] = [],
        workouts: [WorkoutDTO] = [],
        metricSeries: [MetricSeriesPointDTO] = []
    ) {
        self.clientBatchId = clientBatchId
        self.schemaVersion = schemaVersion
        self.appVersion = appVersion
        self.sourceDeviceIds = sourceDeviceIds ?? sources.map(\.sourceDeviceId).sorted()
        self.window = window
        self.sources = sources
        self.dailyMetrics = dailyMetrics
        self.sleepSessions = sleepSessions
        self.workouts = workouts
        self.metricSeries = metricSeries
    }
}
