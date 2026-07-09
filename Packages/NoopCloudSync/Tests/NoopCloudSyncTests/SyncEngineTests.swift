import XCTest
@testable import NoopCloudSync

final class SyncEngineTests: XCTestCase {
    func testDefaultEngineIsDisabledAndDoesNoWork() async {
        let engine = SyncEngine()
        let result = await engine.appDidBecomeActive()
        XCTAssertEqual(result, .skippedDisabled)
    }

    func testDTOsEncodeWithStableTopLevelKeys() throws {
        let batch = CloudSyncBatchDTO(
            clientBatchId: "batch-1",
            schemaVersion: "noop-cloud-sync-v1",
            sources: [CloudSourceDescriptorDTO(sourceDeviceId: "my-whoop", kind: "measuredOrImported")],
            dailyMetrics: [DailyMetricDTO(sourceDeviceId: "my-whoop", day: "2026-07-05", recovery: 34, effort: 11.11)]
        )

        let data = try JSONEncoder().encode(batch)
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]

        XCTAssertEqual(object?["clientBatchId"] as? String, "batch-1")
        XCTAssertEqual(object?["schemaVersion"] as? String, "noop-cloud-sync-v1")
        XCTAssertEqual(object?["sourceDeviceIds"] as? [String], ["my-whoop"])
        XCTAssertNotNil(object?["sources"])
        XCTAssertNotNil(object?["dailyMetrics"])
        XCTAssertNotNil(object?["sleepSessions"])
        XCTAssertNotNil(object?["workouts"])
        XCTAssertNotNil(object?["metricSeries"])
    }

    func testReadOnlySQLiteAdapterExtractsBackupSnapshotWhenAvailable() async throws {
        let databasePath = backupDatabasePath()
        guard FileManager.default.fileExists(atPath: databasePath) else {
            throw XCTSkip("No extracted Noop backup database found at \(databasePath)")
        }

        let adapter = SQLiteLocalReadAdapter(databasePath: databasePath)
        let request = CloudReadRequest(
            sourceDeviceIds: ["my-whoop", "my-whoop-noop"],
            windowDays: 30,
            fromDay: "2026-06-06",
            toDay: "2026-07-06",
            fromTs: 1780704000,
            toTs: 1783382399
        )

        let snapshot = try await adapter.readSnapshot(request)
        let summary = CloudSnapshotSummary.make(from: snapshot, request: request)

        XCTAssertEqual(summary.countsBySource["my-whoop"]?.dailyMetrics, 1)
        XCTAssertEqual(summary.countsBySource["my-whoop-noop"]?.dailyMetrics, 20)
        XCTAssertEqual(summary.countsBySource["my-whoop"]?.sleepSessions, 2)
        XCTAssertEqual(summary.countsBySource["my-whoop-noop"]?.sleepSessions, 19)
        XCTAssertEqual(summary.countsBySource["my-whoop"]?.workouts, 17)
        XCTAssertEqual(summary.countsBySource["my-whoop-noop"]?.workouts, 0)

        XCTAssertEqual(summary.metricSeriesKeysBySource["my-whoop"], ["sleep_mark", "sleep_performance"])
        XCTAssertEqual(summary.metricSeriesKeysBySource["my-whoop-noop"], ["body_age", "fitness_age", "sleep_performance", "vitality", "vo2max_est"])
        XCTAssertFalse(summary.containsSleepDebtMetric)
        XCTAssertEqual(summary.maxDailyEffort ?? 0, 53.94, accuracy: 0.001)
        XCTAssertEqual(summary.maxWorkoutEffort ?? 0, 56.730000000000004, accuracy: 0.001)

        XCTAssertTrue(snapshot.dailyMetrics.allSatisfy { ["my-whoop", "my-whoop-noop"].contains($0.sourceDeviceId) })
        XCTAssertTrue(snapshot.sleepSessions.allSatisfy { ["my-whoop", "my-whoop-noop"].contains($0.sourceDeviceId) })
        XCTAssertTrue(snapshot.workouts.allSatisfy { ["my-whoop", "my-whoop-noop"].contains($0.sourceDeviceId) })
        XCTAssertTrue(snapshot.metricSeries.allSatisfy { ["my-whoop", "my-whoop-noop"].contains($0.sourceDeviceId) })
    }

    func testHTTPUploadPostsBatchWithBearerTokenAndBothSources() async throws {
        let transport = CapturingHTTPTransport()
        let client = HTTPAPIClient(transport: transport)
        let batch = CloudSyncBatchDTO(
            clientBatchId: "batch-123",
            schemaVersion: "noop-cloud-sync-v1",
            appVersion: "1.2.3",
            sources: [
                CloudSourceDescriptorDTO(sourceDeviceId: "my-whoop", kind: "localSQLite"),
                CloudSourceDescriptorDTO(sourceDeviceId: "my-whoop-noop", kind: "localSQLite")
            ],
            dailyMetrics: [
                DailyMetricDTO(sourceDeviceId: "my-whoop", day: "2026-07-05", effort: 53.94),
                DailyMetricDTO(sourceDeviceId: "my-whoop-noop", day: "2026-07-05", effort: 12.3)
            ]
        )

        let response = try await client.uploadBatch(
            batch,
            identity: CloudDeviceIdentity(cloudDeviceId: "cloud-device-1", deviceToken: "stable-token"),
            config: CloudConfig(isEnabled: true, serverURL: URL(string: "https://cloud.example.test")!)
        )

        let request = await transport.capturedRequest
        XCTAssertEqual(request?.url?.absoluteString, "https://cloud.example.test/v1/sync/batch")
        XCTAssertEqual(request?.httpMethod, "POST")
        XCTAssertEqual(request?.value(forHTTPHeaderField: "Authorization"), "Bearer stable-token")
        XCTAssertEqual(request?.value(forHTTPHeaderField: "Content-Type"), "application/json")

        let body = try XCTUnwrap(request?.httpBody)
        let object = try JSONSerialization.jsonObject(with: body) as? [String: Any]
        XCTAssertEqual(object?["clientBatchId"] as? String, "batch-123")
        XCTAssertEqual(object?["schemaVersion"] as? String, "noop-cloud-sync-v1")
        XCTAssertEqual(object?["appVersion"] as? String, "1.2.3")
        XCTAssertEqual(object?["sourceDeviceIds"] as? [String], ["my-whoop", "my-whoop-noop"])
        XCTAssertNotNil(object?["window"])
        XCTAssertNotNil(object?["dailyMetrics"])
        XCTAssertNotNil(object?["sleepSessions"])
        XCTAssertNotNil(object?["workouts"])
        XCTAssertNotNil(object?["metricSeries"])
        XCTAssertEqual(response.acceptedDailyMetrics, 2)
    }

    func testHTTPFriendsClientCallsUserAndFriendEndpointsWithBearerToken() async throws {
        let encoder = JSONEncoder()
        let transport = QueuedHTTPTransport(responses: [
            try encoder.encode(CloudUserMeDTO(device: CloudDeviceDTO(id: "device-1", cloudUserId: "user-1"), user: CloudUserDTO(id: "user-1", username: "ada"))),
            try encoder.encode(CloudUserMeDTO(device: CloudDeviceDTO(id: "device-1", cloudUserId: "user-1"), user: CloudUserDTO(id: "user-1", username: "ada", shareSleep: false))),
            try encoder.encode(FriendRequestResponseDTO(created: true, friendship: FriendshipDTO(id: "friendship-1", requesterUserId: "user-1", addresseeUserId: "user-2", status: "pending"))),
            try encoder.encode(FriendsListDTO(friends: [])),
            try encoder.encode(FriendRequestsDTO(incoming: [], outgoing: [])),
            try encoder.encode(FriendsFeedDTO(friends: []))
        ])
        let client = HTTPFriendsClient(transport: transport)
        let identity = CloudDeviceIdentity(cloudDeviceId: "device-1", deviceToken: "stable-token")
        let config = CloudConfig(isEnabled: true, serverURL: URL(string: "https://cloud.example.test")!)

        _ = try await client.bootstrapUser(CloudUserProfileRequest(username: "Ada", displayName: "Ada Lovelace"), identity: identity, config: config)
        _ = try await client.updatePrivacy(CloudUserPrivacyRequest(shareSleep: false), identity: identity, config: config)
        _ = try await client.requestFriend(FriendRequestCreateDTO(username: "bob"), identity: identity, config: config)
        _ = try await client.friends(identity: identity, config: config)
        _ = try await client.friendRequests(identity: identity, config: config)
        _ = try await client.feed(identity: identity, config: config)

        let requests = await transport.requests
        XCTAssertEqual(requests.map { $0.url?.path }, [
            "/v1/user/bootstrap",
            "/v1/user/privacy",
            "/v1/friends/request",
            "/v1/friends",
            "/v1/friends/requests",
            "/v1/friends/feed"
        ])
        XCTAssertTrue(requests.allSatisfy { $0.value(forHTTPHeaderField: "Authorization") == "Bearer stable-token" })
        XCTAssertEqual(requests[0].httpMethod, "POST")
        XCTAssertEqual(requests[1].httpMethod, "PATCH")
        XCTAssertEqual(requests[3].httpMethod, "GET")

        let bootstrapBody = try XCTUnwrap(requests[0].httpBody)
        let bootstrapObject = try JSONSerialization.jsonObject(with: bootstrapBody) as? [String: Any]
        XCTAssertEqual(bootstrapObject?["username"] as? String, "Ada")
        XCTAssertEqual(bootstrapObject?["displayName"] as? String, "Ada Lovelace")

        let privacyBody = try XCTUnwrap(requests[1].httpBody)
        let privacyObject = try JSONSerialization.jsonObject(with: privacyBody) as? [String: Any]
        XCTAssertEqual(privacyObject?["shareSleep"] as? Bool, false)

        let friendRequestBody = try XCTUnwrap(requests[2].httpBody)
        let friendRequestObject = try JSONSerialization.jsonObject(with: friendRequestBody) as? [String: Any]
        XCTAssertEqual(friendRequestObject?["username"] as? String, "bob")
        XCTAssertNil(friendRequestObject?["targetUsername"])
        XCTAssertNil(friendRequestObject?["displayName"])
    }

    func testFriendRequestBodyEncodingMatchesBackendContract() throws {
        let encoder = JSONEncoder()

        let usernameData = try encoder.encode(FriendRequestCreateDTO(username: "bob"))
        let usernameObject = try JSONSerialization.jsonObject(with: usernameData) as? [String: Any]
        XCTAssertEqual(usernameObject?["username"] as? String, "bob")
        XCTAssertNil(usernameObject?["userId"])
        XCTAssertNil(usernameObject?["user_id"])

        let userIdData = try encoder.encode(FriendRequestCreateDTO(userId: "user-2"))
        let userIdObject = try JSONSerialization.jsonObject(with: userIdData) as? [String: Any]
        XCTAssertEqual(userIdObject?["user_id"] as? String, "user-2")
        XCTAssertNil(userIdObject?["userId"])
        XCTAssertNil(userIdObject?["username"])
    }

    func testHTTPFriendsClientDecodesBackendErrorBodies() async throws {
        let transport = FixedHTTPTransport(
            statusCode: 409,
            data: try JSONEncoder().encode(CloudAPIErrorDTO(error: "username_conflict"))
        )
        let client = HTTPFriendsClient(transport: transport)

        do {
            _ = try await client.bootstrapUser(
                CloudUserProfileRequest(username: "ada"),
                identity: CloudDeviceIdentity(deviceToken: "stable-token"),
                config: CloudConfig(isEnabled: true, serverURL: URL(string: "https://cloud.example.test")!)
            )
            XCTFail("Expected username conflict")
        } catch let error as CloudFriendsClientError {
            XCTAssertEqual(error, .server(statusCode: 409, code: "username_conflict", detail: nil))
            XCTAssertEqual(error.localizedDescription, "That username is already taken.")
        }
    }

    func testUploadDoesNotReadOrPostWhenCloudIsDisabled() async {
        let adapter = CountingReadAdapter()
        let apiClient = CountingAPIClient()
        let engine = SyncEngine(
            configProvider: StaticCloudConfigProvider(config: .disabled),
            identityStore: InMemoryIdentityStore(identity: CloudDeviceIdentity(deviceToken: "token")),
            localReadAdapter: adapter,
            apiClient: apiClient
        )

        let result = await engine.uploadSnapshot(CloudReadRequest())

        XCTAssertEqual(result, .skippedDisabled)
        let readCount = await adapter.readCount
        let uploadCount = await apiClient.uploadCount
        XCTAssertEqual(readCount, 0)
        XCTAssertEqual(uploadCount, 0)
    }

    func testBackupSnapshotReadDoesNotModifySQLiteFileWhenAvailable() async throws {
        let databasePath = backupDatabasePath()
        guard FileManager.default.fileExists(atPath: databasePath) else {
            throw XCTSkip("No extracted Noop backup database found at \(databasePath)")
        }

        let before = try sqliteModificationDate(databasePath)
        let adapter = SQLiteLocalReadAdapter(databasePath: databasePath)
        _ = try await adapter.readSnapshot(CloudReadRequest(
            sourceDeviceIds: ["my-whoop", "my-whoop-noop"],
            windowDays: 30,
            fromDay: "2026-06-06",
            toDay: "2026-07-06",
            fromTs: 1780704000,
            toTs: 1783382399
        ))
        let after = try sqliteModificationDate(databasePath)

        XCTAssertEqual(before, after)
    }

    private func backupDatabasePath() -> String {
        ProcessInfo.processInfo.environment["NOOP_CLOUD_TEST_DB"]
            ?? "/Users/adamleko/Documents/Codex/2026-07-06/i-am-working-on-a-different/work/noopbak/noop-backup.sqlite"
    }

    private func sqliteModificationDate(_ path: String) throws -> Date {
        try XCTUnwrap(FileManager.default.attributesOfItem(atPath: path)[.modificationDate] as? Date)
    }
}

private actor CapturingHTTPTransport: HTTPTransport {
    private(set) var capturedRequest: URLRequest?

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        capturedRequest = request
        let response = SyncUploadResponse(acceptedDailyMetrics: 2)
        let data = try JSONEncoder().encode(response)
        let httpResponse = HTTPURLResponse(url: request.url!, statusCode: 202, httpVersion: nil, headerFields: nil)!
        return (data, httpResponse)
    }
}

private actor QueuedHTTPTransport: HTTPTransport {
    private(set) var requests: [URLRequest] = []
    private var responses: [Data]

    init(responses: [Data]) {
        self.responses = responses
    }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        requests.append(request)
        let data = responses.removeFirst()
        let httpResponse = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        return (data, httpResponse)
    }
}

private actor FixedHTTPTransport: HTTPTransport {
    private let statusCode: Int
    private let data: Data

    init(statusCode: Int, data: Data) {
        self.statusCode = statusCode
        self.data = data
    }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let httpResponse = HTTPURLResponse(url: request.url!, statusCode: statusCode, httpVersion: nil, headerFields: nil)!
        return (data, httpResponse)
    }
}

private actor CountingReadAdapter: LocalReadAdapter {
    private(set) var readCount = 0

    func readSnapshot(_ request: CloudReadRequest) async throws -> CloudReadSnapshot {
        _ = request
        readCount += 1
        return CloudReadSnapshot()
    }
}

private actor CountingAPIClient: APIClient {
    private(set) var uploadCount = 0

    func registerDevice(_ request: DeviceRegistrationRequest, config: CloudConfig) async throws -> DeviceRegistrationResponse {
        _ = request
        _ = config
        throw APIClientError.notImplemented
    }

    func uploadBatch(_ batch: CloudSyncBatchDTO, identity: CloudDeviceIdentity, config: CloudConfig) async throws -> SyncUploadResponse {
        _ = batch
        _ = identity
        _ = config
        uploadCount += 1
        return SyncUploadResponse()
    }
}

private actor InMemoryIdentityStore: IdentityStore {
    private var identity: CloudDeviceIdentity?

    init(identity: CloudDeviceIdentity?) {
        self.identity = identity
    }

    func loadIdentity() async throws -> CloudDeviceIdentity? {
        identity
    }

    func saveIdentity(_ identity: CloudDeviceIdentity) async throws {
        self.identity = identity
    }

    func clearIdentity() async throws {
        identity = nil
    }
}
