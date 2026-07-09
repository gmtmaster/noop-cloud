import Foundation
import NoopCloudSync

@main
struct UploadCommand {
    static func main() async throws {
        let options = parse(Array(CommandLine.arguments.dropFirst()))
        let databasePath = options.databasePath ?? DefaultNoopDatabaseLocator().firstExistingDatabasePath()
        guard let databasePath else { throw CommandError.missingDatabasePath }
        guard let serverURL = URL(string: options.serverURL) else { throw CommandError.invalidServerURL(options.serverURL) }
        guard !options.token.isEmpty else { throw CommandError.missingToken }

        let request = CloudReadRequest(
            sourceDeviceIds: options.sourceDeviceIds,
            windowDays: options.windowDays,
            metricSeriesKeys: options.metricSeriesKeys,
            fromDay: options.fromDay,
            toDay: options.toDay,
            fromTs: options.fromTs,
            toTs: options.toTs
        )

        let config = CloudConfig(
            isEnabled: true,
            serverURL: serverURL,
            uploadWindowDays: options.windowDays,
            schemaVersion: options.schemaVersion,
            appVersion: options.appVersion
        )

        let adapter = SQLiteLocalReadAdapter(databasePath: databasePath)
        let snapshot = try await adapter.readSnapshot(request)
        let batch = CloudSyncBatchFactory.makeBatch(
            snapshot: snapshot,
            request: request,
            config: config,
            clientBatchId: options.clientBatchId
        )

        let response = try await HTTPAPIClient().uploadBatch(
            batch,
            identity: CloudDeviceIdentity(cloudDeviceId: "local-e2e", deviceToken: options.token),
            config: config
        )

        let result = UploadResult(
            clientBatchId: batch.clientBatchId,
            sourceDeviceIds: batch.sourceDeviceIds,
            sentDailyMetrics: batch.dailyMetrics.count,
            sentSleepSessions: batch.sleepSessions.count,
            sentWorkouts: batch.workouts.count,
            sentMetricSeries: batch.metricSeries.count,
            response: response
        )

        let data = try CloudSnapshotSerializer.prettyJSON(result)
        FileHandle.standardOutput.write(data)
        FileHandle.standardOutput.write(Data("\n".utf8))
    }

    private static func parse(_ arguments: [String]) -> Options {
        var options = Options()
        var index = 0

        while index < arguments.count {
            let argument = arguments[index]
            let next = index + 1 < arguments.count ? arguments[index + 1] : nil

            switch argument {
            case "--db":
                options.databasePath = next
                index += 2
            case "--server":
                options.serverURL = next ?? options.serverURL
                index += 2
            case "--token":
                options.token = next ?? options.token
                index += 2
            case "--batch-id":
                options.clientBatchId = next ?? options.clientBatchId
                index += 2
            case "--app-version":
                options.appVersion = next
                index += 2
            case "--schema-version":
                options.schemaVersion = next ?? options.schemaVersion
                index += 2
            case "--days":
                options.windowDays = next.flatMap(Int.init) ?? options.windowDays
                index += 2
            case "--source":
                if let next { options.sourceDeviceIds.append(next) }
                index += 2
            case "--metric-key":
                if let next { options.metricSeriesKeys.append(next) }
                index += 2
            case "--from-day":
                options.fromDay = next
                index += 2
            case "--to-day":
                options.toDay = next
                index += 2
            case "--from-ts":
                options.fromTs = next.flatMap(Int.init)
                index += 2
            case "--to-ts":
                options.toTs = next.flatMap(Int.init)
                index += 2
            default:
                index += 1
            }
        }

        if options.sourceDeviceIds.isEmpty {
            options.sourceDeviceIds = ["my-whoop", "my-whoop-noop"]
        }

        return options
    }

    private struct Options {
        var databasePath: String?
        var serverURL: String = "http://127.0.0.1:8787"
        var token: String = "local-e2e-token"
        var clientBatchId: String = UUID().uuidString
        var appVersion: String?
        var schemaVersion: String = "noop-cloud-sync-v1"
        var sourceDeviceIds: [String] = []
        var windowDays: Int = 30
        var metricSeriesKeys: [String] = []
        var fromDay: String?
        var toDay: String?
        var fromTs: Int?
        var toTs: Int?
    }

    private struct UploadResult: Codable {
        var clientBatchId: String
        var sourceDeviceIds: [String]
        var sentDailyMetrics: Int
        var sentSleepSessions: Int
        var sentWorkouts: Int
        var sentMetricSeries: Int
        var response: SyncUploadResponse
    }

    private enum CommandError: Error {
        case missingDatabasePath
        case invalidServerURL(String)
        case missingToken
    }
}
