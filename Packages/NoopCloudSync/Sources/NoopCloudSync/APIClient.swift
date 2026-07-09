import Foundation

public struct DeviceRegistrationRequest: Codable, Equatable, Sendable {
    public var primaryNoopDeviceId: String
    public var displayName: String?
    public var appVersion: String?
    public var schemaVersion: String

    public init(
        primaryNoopDeviceId: String,
        displayName: String? = nil,
        appVersion: String? = nil,
        schemaVersion: String
    ) {
        self.primaryNoopDeviceId = primaryNoopDeviceId
        self.displayName = displayName
        self.appVersion = appVersion
        self.schemaVersion = schemaVersion
    }
}

public struct DeviceRegistrationResponse: Codable, Equatable, Sendable {
    public var cloudDeviceId: String
    public var deviceToken: String
    public var uploadPath: String

    public init(cloudDeviceId: String, deviceToken: String, uploadPath: String = "/v1/sync/batch") {
        self.cloudDeviceId = cloudDeviceId
        self.deviceToken = deviceToken
        self.uploadPath = uploadPath
    }
}

public struct SyncUploadResponse: Codable, Equatable, Sendable {
    public var acceptedDailyMetrics: Int
    public var acceptedSleepSessions: Int
    public var acceptedWorkouts: Int
    public var acceptedMetricSeries: Int
    public var duplicate: Bool?
    public var clientBatchId: String?

    public init(
        acceptedDailyMetrics: Int = 0,
        acceptedSleepSessions: Int = 0,
        acceptedWorkouts: Int = 0,
        acceptedMetricSeries: Int = 0,
        duplicate: Bool? = nil,
        clientBatchId: String? = nil
    ) {
        self.acceptedDailyMetrics = acceptedDailyMetrics
        self.acceptedSleepSessions = acceptedSleepSessions
        self.acceptedWorkouts = acceptedWorkouts
        self.acceptedMetricSeries = acceptedMetricSeries
        self.duplicate = duplicate
        self.clientBatchId = clientBatchId
    }
}

public protocol APIClient: Sendable {
    func registerDevice(_ request: DeviceRegistrationRequest, config: CloudConfig) async throws -> DeviceRegistrationResponse
    func uploadBatch(_ batch: CloudSyncBatchDTO, identity: CloudDeviceIdentity, config: CloudConfig) async throws -> SyncUploadResponse
}

public enum APIClientError: Error, Equatable {
    case disabled
    case notImplemented
    case missingServerURL
    case missingDeviceToken
    case invalidResponse
    case httpStatus(Int)
}

/// Phase-1 client. It never performs network IO; real HTTP transport belongs to Phase 3.
public struct DisabledAPIClient: APIClient {
    public init() {}

    public func registerDevice(_ request: DeviceRegistrationRequest, config: CloudConfig) async throws -> DeviceRegistrationResponse {
        _ = request
        _ = config
        throw APIClientError.disabled
    }

    public func uploadBatch(_ batch: CloudSyncBatchDTO, identity: CloudDeviceIdentity, config: CloudConfig) async throws -> SyncUploadResponse {
        _ = batch
        _ = identity
        _ = config
        throw APIClientError.disabled
    }
}

public protocol HTTPTransport: Sendable {
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

public struct URLSessionHTTPTransport: HTTPTransport {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIClientError.invalidResponse
        }
        return (data, httpResponse)
    }
}

public struct HTTPAPIClient: APIClient {
    private let transport: HTTPTransport
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(
        transport: HTTPTransport = URLSessionHTTPTransport(),
        encoder: JSONEncoder = JSONEncoder(),
        decoder: JSONDecoder = JSONDecoder()
    ) {
        self.transport = transport
        self.encoder = encoder
        self.decoder = decoder
    }

    public func registerDevice(_ request: DeviceRegistrationRequest, config: CloudConfig) async throws -> DeviceRegistrationResponse {
        _ = request
        _ = config
        throw APIClientError.notImplemented
    }

    public func uploadBatch(_ batch: CloudSyncBatchDTO, identity: CloudDeviceIdentity, config: CloudConfig) async throws -> SyncUploadResponse {
        guard let serverURL = config.serverURL else { throw APIClientError.missingServerURL }
        guard let deviceToken = identity.deviceToken, !deviceToken.isEmpty else { throw APIClientError.missingDeviceToken }

        var request = URLRequest(url: serverURL.appendingPathComponent("v1/sync/batch"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(deviceToken)", forHTTPHeaderField: "Authorization")
        request.httpBody = try encoder.encode(batch)

        let (data, response) = try await transport.data(for: request)
        guard (200..<300).contains(response.statusCode) else {
            throw APIClientError.httpStatus(response.statusCode)
        }

        if data.isEmpty {
            return SyncUploadResponse(
                acceptedDailyMetrics: batch.dailyMetrics.count,
                acceptedSleepSessions: batch.sleepSessions.count,
                acceptedWorkouts: batch.workouts.count,
                acceptedMetricSeries: batch.metricSeries.count
            )
        }

        return try decoder.decode(SyncUploadResponse.self, from: data)
    }
}
