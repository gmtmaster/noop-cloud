import Foundation
import SQLite3

public enum SQLiteLocalReadAdapterError: Error, Equatable, Sendable {
    case databaseNotFound(String)
    case openFailed(String)
    case prepareFailed(String)
    case stepFailed(String)
    case missingTable(String)
}

public struct SQLiteLocalReadAdapter: LocalReadAdapter {
    public var databasePath: String
    public var dateProvider: @Sendable () -> Date
    public var calendar: Calendar

    public init(
        databasePath: String,
        dateProvider: @escaping @Sendable () -> Date = { Date() },
        calendar: Calendar = SQLiteLocalReadAdapter.defaultCalendar
    ) {
        self.databasePath = databasePath
        self.dateProvider = dateProvider
        self.calendar = calendar
    }

    public func readSnapshot(_ request: CloudReadRequest) async throws -> CloudReadSnapshot {
        let db = try SQLiteReadOnlyDatabase(path: databasePath)
        defer { db.close() }

        for table in ["dailyMetric", "sleepSession", "workout", "metricSeries"] {
            guard try db.tableExists(table) else { throw SQLiteLocalReadAdapterError.missingTable(table) }
        }

        let window = resolvedWindow(for: request)
        var snapshot = CloudReadSnapshot()
        var sourceIdsWithRows = Set<String>()

        for sourceDeviceId in request.sourceDeviceIds {
            let dailyMetrics = try readDailyMetrics(db: db, sourceDeviceId: sourceDeviceId, window: window)
            let sleepSessions = try readSleepSessions(db: db, sourceDeviceId: sourceDeviceId, window: window)
            let workouts = try readWorkouts(db: db, sourceDeviceId: sourceDeviceId, window: window)
            let metricSeries = try readMetricSeries(
                db: db,
                sourceDeviceId: sourceDeviceId,
                metricSeriesKeys: request.metricSeriesKeys,
                window: window
            )

            if !dailyMetrics.isEmpty || !sleepSessions.isEmpty || !workouts.isEmpty || !metricSeries.isEmpty {
                sourceIdsWithRows.insert(sourceDeviceId)
            }

            snapshot.dailyMetrics.append(contentsOf: dailyMetrics)
            snapshot.sleepSessions.append(contentsOf: sleepSessions)
            snapshot.workouts.append(contentsOf: workouts)
            snapshot.metricSeries.append(contentsOf: metricSeries)
        }

        snapshot.sources = sourceIdsWithRows
            .sorted()
            .map { CloudSourceDescriptorDTO(sourceDeviceId: $0, kind: "localSQLite") }

        return snapshot
    }

    private func readDailyMetrics(db: SQLiteReadOnlyDatabase, sourceDeviceId: String, window: ReadWindow) throws -> [DailyMetricDTO] {
        let sql = """
        SELECT deviceId, day, totalSleepMin, efficiency, deepMin, remMin, lightMin, disturbances,
               restingHr, avgHrv, recovery, strain, exerciseCount, spo2Pct, skinTempDevC,
               respRateBpm, steps, activeKcalEst
        FROM dailyMetric
        WHERE deviceId = ? AND day >= ? AND day <= ?
        ORDER BY day ASC
        """

        return try db.query(sql, bindings: [.text(sourceDeviceId), .text(window.fromDay), .text(window.toDay)]) { row in
            DailyMetricDTO(
                sourceDeviceId: row.string(0) ?? sourceDeviceId,
                day: row.string(1) ?? "",
                totalSleepMin: row.double(2),
                efficiency: row.double(3),
                deepMin: row.double(4),
                remMin: row.double(5),
                lightMin: row.double(6),
                disturbances: row.int(7),
                restingHr: row.int(8),
                avgHrv: row.double(9),
                recovery: row.double(10),
                effort: row.double(11),
                exerciseCount: row.int(12),
                spo2Pct: row.double(13),
                skinTempDevC: row.double(14),
                respRateBpm: row.double(15),
                steps: row.int(16),
                activeKcalEst: row.double(17)
            )
        }
    }

    private func readSleepSessions(db: SQLiteReadOnlyDatabase, sourceDeviceId: String, window: ReadWindow) throws -> [SleepSessionDTO] {
        let sql = """
        SELECT deviceId, startTs, endTs, efficiency, restingHr, avgHrv, stagesJSON, userEdited, startTsAdjusted
        FROM sleepSession
        WHERE deviceId = ? AND startTs >= ? AND startTs <= ?
        ORDER BY startTs ASC
        """

        return try db.query(sql, bindings: [.text(sourceDeviceId), .integer(window.fromTs), .integer(window.toTs)]) { row in
            SleepSessionDTO(
                sourceDeviceId: row.string(0) ?? sourceDeviceId,
                startTs: row.int(1) ?? 0,
                endTs: row.int(2) ?? 0,
                efficiency: row.double(3),
                restingHr: row.int(4),
                avgHrv: row.double(5),
                stagesJSON: row.string(6),
                userEdited: row.bool(7),
                startTsAdjusted: row.int(8)
            )
        }
    }

    private func readWorkouts(db: SQLiteReadOnlyDatabase, sourceDeviceId: String, window: ReadWindow) throws -> [WorkoutDTO] {
        let sql = """
        SELECT deviceId, startTs, endTs, sport, source, durationS, energyKcal, avgHr, maxHr, strain, distanceM, zonesJSON
        FROM workout
        WHERE deviceId = ? AND startTs >= ? AND startTs <= ?
        ORDER BY startTs ASC, sport ASC
        """

        return try db.query(sql, bindings: [.text(sourceDeviceId), .integer(window.fromTs), .integer(window.toTs)]) { row in
            WorkoutDTO(
                sourceDeviceId: row.string(0) ?? sourceDeviceId,
                startTs: row.int(1) ?? 0,
                endTs: row.int(2) ?? 0,
                sport: row.string(3) ?? "",
                source: row.string(4) ?? "",
                durationS: row.double(5),
                energyKcal: row.double(6),
                avgHr: row.int(7),
                maxHr: row.int(8),
                effort: row.double(9),
                distanceM: row.double(10),
                zonesJSON: row.string(11)
            )
        }
    }

    private func readMetricSeries(
        db: SQLiteReadOnlyDatabase,
        sourceDeviceId: String,
        metricSeriesKeys: [String],
        window: ReadWindow
    ) throws -> [MetricSeriesPointDTO] {
        var sql = """
        SELECT deviceId, day, key, value
        FROM metricSeries
        WHERE deviceId = ? AND day >= ? AND day <= ?
        """
        var bindings: [SQLiteBinding] = [.text(sourceDeviceId), .text(window.fromDay), .text(window.toDay)]

        if !metricSeriesKeys.isEmpty {
            let placeholders = Array(repeating: "?", count: metricSeriesKeys.count).joined(separator: ",")
            sql += " AND key IN (\(placeholders))"
            bindings.append(contentsOf: metricSeriesKeys.map(SQLiteBinding.text))
        }

        sql += " ORDER BY day ASC, key ASC"

        return try db.query(sql, bindings: bindings) { row in
            MetricSeriesPointDTO(
                sourceDeviceId: row.string(0) ?? sourceDeviceId,
                day: row.string(1) ?? "",
                key: row.string(2) ?? "",
                value: row.double(3) ?? 0
            )
        }
    }

    private func resolvedWindow(for request: CloudReadRequest) -> ReadWindow {
        let now = dateProvider()
        let toDay = request.toDay ?? Self.dayFormatter.string(from: now)
        let fromDate = calendar.date(byAdding: .day, value: -max(request.windowDays - 1, 0), to: now) ?? now
        let fromDay = request.fromDay ?? Self.dayFormatter.string(from: fromDate)
        let toTs = request.toTs ?? Int(now.timeIntervalSince1970)
        let fromTs = request.fromTs ?? Int(fromDate.timeIntervalSince1970)

        return ReadWindow(fromDay: fromDay, toDay: toDay, fromTs: fromTs, toTs: toTs)
    }

    public static var defaultCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        return calendar
    }

    private static var dayFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.calendar = defaultCalendar
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }

    private struct ReadWindow {
        var fromDay: String
        var toDay: String
        var fromTs: Int
        var toTs: Int
    }
}

private enum SQLiteBinding {
    case text(String)
    case integer(Int)
}

private final class SQLiteReadOnlyDatabase {
    private var handle: OpaquePointer?

    init(path: String) throws {
        guard FileManager.default.fileExists(atPath: path) else {
            throw SQLiteLocalReadAdapterError.databaseNotFound(path)
        }

        var db: OpaquePointer?
        let flags = SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX
        guard sqlite3_open_v2(path, &db, flags, nil) == SQLITE_OK, let opened = db else {
            let message = db.map { String(cString: sqlite3_errmsg($0)) } ?? "unknown SQLite open error"
            if let db {
                sqlite3_close(db)
            }
            throw SQLiteLocalReadAdapterError.openFailed(message)
        }

        handle = opened
    }

    func close() {
        if let handle {
            sqlite3_close(handle)
            self.handle = nil
        }
    }

    func tableExists(_ tableName: String) throws -> Bool {
        let sql = "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = ? LIMIT 1"
        let rows: [Int] = try query(sql, bindings: [.text(tableName)]) { _ in 1 }
        return !rows.isEmpty
    }

    func query<T>(_ sql: String, bindings: [SQLiteBinding], rowBuilder: (SQLiteRow) throws -> T) throws -> [T] {
        guard let handle else { throw SQLiteLocalReadAdapterError.openFailed("database is closed") }

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK, let prepared = statement else {
            throw SQLiteLocalReadAdapterError.prepareFailed(String(cString: sqlite3_errmsg(handle)))
        }
        defer { sqlite3_finalize(prepared) }

        for (index, binding) in bindings.enumerated() {
            let sqliteIndex = Int32(index + 1)
            switch binding {
            case let .text(value):
                sqlite3_bind_text(prepared, sqliteIndex, value, -1, SQLITE_TRANSIENT)
            case let .integer(value):
                sqlite3_bind_int64(prepared, sqliteIndex, sqlite3_int64(value))
            }
        }

        var rows: [T] = []
        while true {
            let result = sqlite3_step(prepared)
            switch result {
            case SQLITE_ROW:
                rows.append(try rowBuilder(SQLiteRow(statement: prepared)))
            case SQLITE_DONE:
                return rows
            default:
                throw SQLiteLocalReadAdapterError.stepFailed(String(cString: sqlite3_errmsg(handle)))
            }
        }
    }
}

private struct SQLiteRow {
    var statement: OpaquePointer

    func string(_ index: Int32) -> String? {
        guard sqlite3_column_type(statement, index) != SQLITE_NULL, let text = sqlite3_column_text(statement, index) else {
            return nil
        }
        return String(cString: text)
    }

    func int(_ index: Int32) -> Int? {
        guard sqlite3_column_type(statement, index) != SQLITE_NULL else { return nil }
        return Int(sqlite3_column_int64(statement, index))
    }

    func double(_ index: Int32) -> Double? {
        guard sqlite3_column_type(statement, index) != SQLITE_NULL else { return nil }
        return sqlite3_column_double(statement, index)
    }

    func bool(_ index: Int32) -> Bool? {
        int(index).map { $0 != 0 }
    }
}

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
