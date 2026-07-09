import Foundation

public struct CloudSyncCursor: Equatable, Sendable {
    public var lastSuccessfulSyncAt: Date?
    public var tableCursors: [String: String]

    public init(lastSuccessfulSyncAt: Date? = nil, tableCursors: [String: String] = [:]) {
        self.lastSuccessfulSyncAt = lastSuccessfulSyncAt
        self.tableCursors = tableCursors
    }
}

public protocol CursorStore: Sendable {
    func loadCursor() async throws -> CloudSyncCursor
    func saveCursor(_ cursor: CloudSyncCursor) async throws
    func clearCursor() async throws
}

public actor InMemoryCursorStore: CursorStore {
    private var cursor: CloudSyncCursor

    public init(cursor: CloudSyncCursor = CloudSyncCursor()) {
        self.cursor = cursor
    }

    public func loadCursor() async throws -> CloudSyncCursor {
        cursor
    }

    public func saveCursor(_ cursor: CloudSyncCursor) async throws {
        self.cursor = cursor
    }

    public func clearCursor() async throws {
        cursor = CloudSyncCursor()
    }
}

