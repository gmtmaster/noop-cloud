import Foundation

public enum SyncRunResult: Equatable, Sendable {
    case skippedDisabled
    case skippedUnregistered
    case preparedEmptyBatch
    case uploaded(SyncUploadResponse)
}

public actor SyncEngine {
    private let configProvider: CloudConfigProviding
    private let identityStore: IdentityStore
    private let cursorStore: CursorStore
    private let localReadAdapter: LocalReadAdapter
    private let apiClient: APIClient

    public init(
        configProvider: CloudConfigProviding = StaticCloudConfigProvider(),
        identityStore: IdentityStore = DisabledIdentityStore(),
        cursorStore: CursorStore = InMemoryCursorStore(),
        localReadAdapter: LocalReadAdapter = EmptyLocalReadAdapter(),
        apiClient: APIClient = DisabledAPIClient()
    ) {
        self.configProvider = configProvider
        self.identityStore = identityStore
        self.cursorStore = cursorStore
        self.localReadAdapter = localReadAdapter
        self.apiClient = apiClient
    }

    /// Foreground hook for the app. In Phase 1 this returns before reading SQLite or touching the network
    /// because the default config is disabled.
    public func appDidBecomeActive() async -> SyncRunResult {
        let config = await configProvider.loadCloudConfig()
        guard config.isEnabled else { return .skippedDisabled }

        do {
            guard let identity = try await identityStore.loadIdentity(), identity.isRegistered else {
                return .skippedUnregistered
            }

            _ = try await cursorStore.loadCursor()
            let request = CloudReadRequest(windowDays: config.uploadWindowDays)
            let snapshot = try await localReadAdapter.readSnapshot(request)
            let batch = CloudSyncBatchFactory.makeBatch(snapshot: snapshot, request: request, config: config)

            guard !batch.dailyMetrics.isEmpty || !batch.sleepSessions.isEmpty || !batch.workouts.isEmpty || !batch.metricSeries.isEmpty else {
                return .preparedEmptyBatch
            }

            let response = try await apiClient.uploadBatch(batch, identity: identity, config: config)
            try await cursorStore.saveCursor(CloudSyncCursor(lastSuccessfulSyncAt: Date()))
            return .uploaded(response)
        } catch {
            return .preparedEmptyBatch
        }
    }

    public func uploadSnapshot(_ request: CloudReadRequest) async -> SyncRunResult {
        let config = await configProvider.loadCloudConfig()
        guard config.isEnabled else { return .skippedDisabled }

        do {
            guard let identity = try await identityStore.loadIdentity(), identity.isRegistered else {
                return .skippedUnregistered
            }

            let snapshot = try await localReadAdapter.readSnapshot(request)
            let batch = CloudSyncBatchFactory.makeBatch(snapshot: snapshot, request: request, config: config)

            guard !batch.dailyMetrics.isEmpty || !batch.sleepSessions.isEmpty || !batch.workouts.isEmpty || !batch.metricSeries.isEmpty else {
                return .preparedEmptyBatch
            }

            let response = try await apiClient.uploadBatch(batch, identity: identity, config: config)
            try await cursorStore.saveCursor(CloudSyncCursor(lastSuccessfulSyncAt: Date()))
            return .uploaded(response)
        } catch {
            return .preparedEmptyBatch
        }
    }

}
