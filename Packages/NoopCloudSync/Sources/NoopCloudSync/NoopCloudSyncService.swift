import Foundation

public final class NoopCloudSyncService: @unchecked Sendable {
    public static let shared = NoopCloudSyncService()

    private let engine: SyncEngine

    public init(engine: SyncEngine = SyncEngine()) {
        self.engine = engine
    }

    /// Fire-and-forget app lifecycle entry point. The default engine is disabled, so this is a no-op
    /// until a later phase wires explicit user opt-in and real dependencies.
    public func appDidBecomeActive() {
        Task {
            _ = await engine.appDidBecomeActive()
        }
    }

    public func makeLocalSnapshotSummary(databasePath: String, request: CloudReadRequest = CloudReadRequest()) async throws -> CloudSnapshotSummary {
        let adapter = SQLiteLocalReadAdapter(databasePath: databasePath)
        let snapshot = try await adapter.readSnapshot(request)
        return CloudSnapshotSummary.make(from: snapshot, request: request)
    }

    public func uploadLocalSnapshot(databasePath: String, request: CloudReadRequest = CloudReadRequest(), config: CloudConfig) async -> SyncRunResult {
        let engine = SyncEngine(
            configProvider: StaticCloudConfigProvider(config: config),
            identityStore: KeychainIdentityStore(),
            localReadAdapter: SQLiteLocalReadAdapter(databasePath: databasePath),
            apiClient: HTTPAPIClient()
        )
        return await engine.uploadSnapshot(request)
    }
}
