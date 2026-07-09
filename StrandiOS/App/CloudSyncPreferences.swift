#if os(iOS)
import Foundation
import NoopCloudSync

enum CloudSyncPreferences {
    static let loginRequiredMessage = "Log in or create a cloud profile before enabling sync."

    static let enabledKey = "noop.cloud.enabled"
    static let serverURLKey = "noop.cloud.serverURL"
    static let intervalMinutesKey = "noop.cloud.intervalMinutes"
    static let lastAttemptAtKey = "noop.cloud.lastAttemptAt"
    static let lastSuccessAtKey = "noop.cloud.lastSuccessAt"
    static let lastStatusKey = "noop.cloud.lastStatus"
    static let lastAcceptedDailyMetricsKey = "noop.cloud.lastAcceptedDailyMetrics"
    static let lastAcceptedSleepSessionsKey = "noop.cloud.lastAcceptedSleepSessions"
    static let lastAcceptedWorkoutsKey = "noop.cloud.lastAcceptedWorkouts"
    static let lastAcceptedMetricSeriesKey = "noop.cloud.lastAcceptedMetricSeries"

    static func config(defaults: UserDefaults = .standard) -> CloudConfig {
        let base = connectionConfig(defaults: defaults)
        return CloudConfig(
            isEnabled: defaults.bool(forKey: enabledKey) && CloudUserSession.isLoggedIn(defaults: defaults),
            serverURL: base.serverURL,
            uploadWindowDays: base.uploadWindowDays,
            schemaVersion: base.schemaVersion,
            appVersion: base.appVersion
        )
    }

    static func connectionConfig(defaults: UserDefaults = .standard) -> CloudConfig {
        let rawURL = defaults.string(forKey: serverURLKey) ?? ""
        return CloudConfig(
            isEnabled: true,
            serverURL: URL(string: rawURL.trimmingCharacters(in: .whitespacesAndNewlines)),
            uploadWindowDays: 30,
            schemaVersion: "noop-cloud-sync-v1",
            appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
        )
    }

    static func setEnabled(_ enabled: Bool, defaults: UserDefaults = .standard) {
        defaults.set(enabled && CloudUserSession.isLoggedIn(defaults: defaults), forKey: enabledKey)
    }

    static func request(defaults: UserDefaults = .standard) -> CloudReadRequest {
        CloudReadRequest(sourceDeviceIds: ["my-whoop", "my-whoop-noop"], windowDays: 30)
    }

    static func intervalMinutes(defaults: UserDefaults = .standard) -> Int {
        defaults.object(forKey: intervalMinutesKey) as? Int ?? 0
    }

    static func saveSuccess(_ response: SyncUploadResponse, now: Date = Date(), defaults: UserDefaults = .standard) {
        defaults.set(now.timeIntervalSince1970, forKey: lastAttemptAtKey)
        defaults.set(now.timeIntervalSince1970, forKey: lastSuccessAtKey)
        defaults.set("Success", forKey: lastStatusKey)
        defaults.set(response.acceptedDailyMetrics, forKey: lastAcceptedDailyMetricsKey)
        defaults.set(response.acceptedSleepSessions, forKey: lastAcceptedSleepSessionsKey)
        defaults.set(response.acceptedWorkouts, forKey: lastAcceptedWorkoutsKey)
        defaults.set(response.acceptedMetricSeries, forKey: lastAcceptedMetricSeriesKey)
    }

    static func saveFailure(_ message: String, now: Date = Date(), defaults: UserDefaults = .standard) {
        defaults.set(now.timeIntervalSince1970, forKey: lastAttemptAtKey)
        defaults.set("Failed: \(message)", forKey: lastStatusKey)
    }
}

enum CloudSyncInterval: Int, CaseIterable, Identifiable {
    case manual = 0
    case fifteen = 15
    case thirty = 30
    case hourly = 60
    case threeHours = 180
    case daily = 1440

    var id: Int { rawValue }

    var label: String {
        switch self {
        case .manual: "Manual only"
        case .fifteen: "Every 15 minutes"
        case .thirty: "Every 30 minutes"
        case .hourly: "Every 1 hour"
        case .threeHours: "Every 3 hours"
        case .daily: "Once per day"
        }
    }
}
#endif
