import Foundation
import NoopCloudSync

@main
struct SnapshotCommand {
    static func main() async throws {
        let arguments = Array(CommandLine.arguments.dropFirst())
        let options = parse(arguments)

        let databasePath = options.databasePath ?? DefaultNoopDatabaseLocator().firstExistingDatabasePath()
        guard let databasePath else {
            throw CommandError.missingDatabasePath
        }

        let request = CloudReadRequest(
            sourceDeviceIds: options.sourceDeviceIds,
            windowDays: options.windowDays,
            metricSeriesKeys: options.metricSeriesKeys,
            fromDay: options.fromDay,
            toDay: options.toDay,
            fromTs: options.fromTs,
            toTs: options.toTs
        )

        let adapter = SQLiteLocalReadAdapter(databasePath: databasePath)
        let snapshot = try await adapter.readSnapshot(request)
        let summary = CloudSnapshotSummary.make(from: snapshot, request: request)
        let data = try CloudSnapshotSerializer.prettyJSON(summary)

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
            case "--days":
                options.windowDays = next.flatMap(Int.init) ?? options.windowDays
                index += 2
            case "--source":
                if let next {
                    options.sourceDeviceIds.append(next)
                }
                index += 2
            case "--metric-key":
                if let next {
                    options.metricSeriesKeys.append(next)
                }
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
        var sourceDeviceIds: [String] = []
        var windowDays: Int = 30
        var metricSeriesKeys: [String] = []
        var fromDay: String?
        var toDay: String?
        var fromTs: Int?
        var toTs: Int?
    }

    private enum CommandError: Error {
        case missingDatabasePath
    }
}
