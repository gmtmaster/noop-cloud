import Foundation

public enum CloudSyncBatchFactory {
    public static func makeBatch(
        snapshot: CloudReadSnapshot,
        request: CloudReadRequest,
        config: CloudConfig,
        clientBatchId: String = UUID().uuidString
    ) -> CloudSyncBatchDTO {
        CloudSyncBatchDTO(
            clientBatchId: clientBatchId,
            schemaVersion: config.schemaVersion,
            appVersion: config.appVersion,
            sourceDeviceIds: snapshot.sources.map(\.sourceDeviceId).sorted(),
            window: CloudSyncWindowDTO(
                fromDay: request.fromDay,
                toDay: request.toDay,
                fromTs: request.fromTs,
                toTs: request.toTs
            ),
            sources: snapshot.sources,
            dailyMetrics: snapshot.dailyMetrics,
            sleepSessions: snapshot.sleepSessions,
            workouts: snapshot.workouts,
            metricSeries: snapshot.metricSeries
        )
    }
}
