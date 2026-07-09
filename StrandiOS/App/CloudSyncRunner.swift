#if os(iOS)
import Foundation
import NoopCloudSync

struct CloudSyncRunSummary: Equatable {
    var response: SyncUploadResponse
    var sentDailyMetrics: Int
    var sentSleepSessions: Int
    var sentWorkouts: Int
    var sentMetricSeries: Int
}

enum CloudSyncRunError: LocalizedError {
    case disabled
    case loginRequired
    case missingServerURL
    case databaseNotFound

    var errorDescription: String? {
        switch self {
        case .disabled: "Cloud Sync is disabled."
        case .loginRequired: CloudSyncPreferences.loginRequiredMessage
        case .missingServerURL: "Enter a server URL first."
        case .databaseNotFound: "No local Noop SQLite database was found."
        }
    }
}

struct CloudSyncRunner {
    var identityStore: IdentityStore = KeychainIdentityStore()
    var databaseLocator: DefaultNoopDatabaseLocator = DefaultNoopDatabaseLocator()
    var apiClient: APIClient = HTTPAPIClient()

    func syncNow(config: CloudConfig, request: CloudReadRequest = CloudSyncPreferences.request()) async throws -> CloudSyncRunSummary {
        guard CloudUserSession.isLoggedIn() else { throw CloudSyncRunError.loginRequired }
        guard config.isEnabled else { throw CloudSyncRunError.disabled }
        guard config.serverURL != nil else { throw CloudSyncRunError.missingServerURL }
        guard let databasePath = databaseLocator.firstExistingDatabasePath() else { throw CloudSyncRunError.databaseNotFound }
        guard let identity = try await identityStore.loadIdentity(), identity.isRegistered else {
            throw APIClientError.missingDeviceToken
        }

        let adapter = SQLiteLocalReadAdapter(databasePath: databasePath)
        let snapshot = try await adapter.readSnapshot(request)
        let batch = CloudSyncBatchFactory.makeBatch(snapshot: snapshot, request: request, config: config)
        let response = try await apiClient.uploadBatch(batch, identity: identity, config: config)

        return CloudSyncRunSummary(
            response: response,
            sentDailyMetrics: batch.dailyMetrics.count,
            sentSleepSessions: batch.sleepSessions.count,
            sentWorkouts: batch.workouts.count,
            sentMetricSeries: batch.metricSeries.count
        )
    }
}

actor CloudSyncForegroundCoordinator {
    static let shared = CloudSyncForegroundCoordinator()
    private var isRunning = false

    func appDidBecomeActive() async {
        let defaults = UserDefaults.standard
        let config = CloudSyncPreferences.config(defaults: defaults)
        guard config.isEnabled, config.serverURL != nil else { return }

        let intervalMinutes = CloudSyncPreferences.intervalMinutes(defaults: defaults)
        guard intervalMinutes > 0 else { return }

        let lastAttempt = defaults.double(forKey: CloudSyncPreferences.lastAttemptAtKey)
        let dueAt = lastAttempt + Double(intervalMinutes * 60)
        guard Date().timeIntervalSince1970 >= dueAt else { return }
        guard !isRunning else { return }

        isRunning = true
        defer { isRunning = false }

        do {
            let summary = try await CloudSyncRunner().syncNow(config: config)
            CloudSyncPreferences.saveSuccess(summary.response, defaults: defaults)
        } catch {
            CloudSyncPreferences.saveFailure(error.localizedDescription, defaults: defaults)
        }
    }
}
#endif
