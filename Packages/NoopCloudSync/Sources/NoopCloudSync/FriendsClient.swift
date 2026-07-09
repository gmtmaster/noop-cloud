import Foundation

public struct FriendSummaryDTO: Codable, Equatable, Sendable {
    public var cloudDeviceId: String
    public var displayName: String
    public var day: String?
    public var recovery: Double?
    public var effort: Double?
    public var totalSleepMin: Double?
    public var sleepDebtMin: Double?
    public var restingHr: Int?
    public var avgHrv: Double?
    public var steps: Int?
    public var latestSleepStart: Int?
    public var latestSleepEnd: Int?

    public init(
        cloudDeviceId: String,
        displayName: String,
        day: String? = nil,
        recovery: Double? = nil,
        effort: Double? = nil,
        totalSleepMin: Double? = nil,
        sleepDebtMin: Double? = nil,
        restingHr: Int? = nil,
        avgHrv: Double? = nil,
        steps: Int? = nil,
        latestSleepStart: Int? = nil,
        latestSleepEnd: Int? = nil
    ) {
        self.cloudDeviceId = cloudDeviceId
        self.displayName = displayName
        self.day = day
        self.recovery = recovery
        self.effort = effort
        self.totalSleepMin = totalSleepMin
        self.sleepDebtMin = sleepDebtMin
        self.restingHr = restingHr
        self.avgHrv = avgHrv
        self.steps = steps
        self.latestSleepStart = latestSleepStart
        self.latestSleepEnd = latestSleepEnd
    }
}

public struct FriendsSummaryDTO: Codable, Equatable, Sendable {
    public var friends: [FriendSummaryDTO]

    public init(friends: [FriendSummaryDTO] = []) {
        self.friends = friends
    }
}

public struct CloudUserDTO: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var username: String?
    public var displayName: String?
    public var avatarUrl: String?
    public var shareRecovery: Bool?
    public var shareSleep: Bool?
    public var shareWorkouts: Bool?
    public var shareDailyEffort: Bool?
    public var createdAt: String?
    public var updatedAt: String?

    public init(
        id: String,
        username: String? = nil,
        displayName: String? = nil,
        avatarUrl: String? = nil,
        shareRecovery: Bool? = nil,
        shareSleep: Bool? = nil,
        shareWorkouts: Bool? = nil,
        shareDailyEffort: Bool? = nil,
        createdAt: String? = nil,
        updatedAt: String? = nil
    ) {
        self.id = id
        self.username = username
        self.displayName = displayName
        self.avatarUrl = avatarUrl
        self.shareRecovery = shareRecovery
        self.shareSleep = shareSleep
        self.shareWorkouts = shareWorkouts
        self.shareDailyEffort = shareDailyEffort
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

public struct CloudAuthSession: Codable, Equatable, Sendable {
    public var token: String

    public init(token: String) {
        self.token = token
    }
}

public struct CloudAuthRequest: Codable, Equatable, Sendable {
    public var username: String
    public var password: String
    public var displayName: String?
    public var avatarUrl: String?

    public init(username: String, password: String, displayName: String? = nil, avatarUrl: String? = nil) {
        self.username = username
        self.password = password
        self.displayName = displayName
        self.avatarUrl = avatarUrl
    }
}

public struct CloudAuthResponseDTO: Codable, Equatable, Sendable {
    public var user: CloudUserDTO
    public var device: CloudDeviceDTO?
    public var sessionToken: String

    public init(user: CloudUserDTO, device: CloudDeviceDTO? = nil, sessionToken: String) {
        self.user = user
        self.device = device
        self.sessionToken = sessionToken
    }
}

public struct CloudDeviceDTO: Codable, Equatable, Sendable {
    public var id: String
    public var cloudUserId: String?
    public var createdAt: String?
    public var lastSeenAt: String?

    public init(id: String, cloudUserId: String? = nil, createdAt: String? = nil, lastSeenAt: String? = nil) {
        self.id = id
        self.cloudUserId = cloudUserId
        self.createdAt = createdAt
        self.lastSeenAt = lastSeenAt
    }
}

public struct CloudUserProfileRequest: Codable, Equatable, Sendable {
    public var username: String?
    public var displayName: String?
    public var avatarUrl: String?

    public init(username: String? = nil, displayName: String? = nil, avatarUrl: String? = nil) {
        self.username = username
        self.displayName = displayName
        self.avatarUrl = avatarUrl
    }
}

public struct CloudUserPrivacyRequest: Codable, Equatable, Sendable {
    public var shareRecovery: Bool?
    public var shareSleep: Bool?
    public var shareWorkouts: Bool?
    public var shareDailyEffort: Bool?

    public init(
        shareRecovery: Bool? = nil,
        shareSleep: Bool? = nil,
        shareWorkouts: Bool? = nil,
        shareDailyEffort: Bool? = nil
    ) {
        self.shareRecovery = shareRecovery
        self.shareSleep = shareSleep
        self.shareWorkouts = shareWorkouts
        self.shareDailyEffort = shareDailyEffort
    }
}

public struct CloudUserMeDTO: Codable, Equatable, Sendable {
    public var device: CloudDeviceDTO?
    public var user: CloudUserDTO?

    public init(device: CloudDeviceDTO? = nil, user: CloudUserDTO? = nil) {
        self.device = device
        self.user = user
    }
}

public struct FriendshipDTO: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var requesterUserId: String
    public var addresseeUserId: String
    public var status: String
    public var createdAt: String?
    public var updatedAt: String?

    public init(
        id: String,
        requesterUserId: String,
        addresseeUserId: String,
        status: String,
        createdAt: String? = nil,
        updatedAt: String? = nil
    ) {
        self.id = id
        self.requesterUserId = requesterUserId
        self.addresseeUserId = addresseeUserId
        self.status = status
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

public struct FriendEntryDTO: Codable, Equatable, Sendable, Identifiable {
    public var friendship: FriendshipDTO
    public var user: CloudUserDTO

    public var id: String { friendship.id }

    public init(friendship: FriendshipDTO, user: CloudUserDTO) {
        self.friendship = friendship
        self.user = user
    }
}

public struct FriendsListDTO: Codable, Equatable, Sendable {
    public var friends: [FriendEntryDTO]

    public init(friends: [FriendEntryDTO] = []) {
        self.friends = friends
    }
}

public struct FriendRequestsDTO: Codable, Equatable, Sendable {
    public var incoming: [FriendEntryDTO]
    public var outgoing: [FriendEntryDTO]

    public init(incoming: [FriendEntryDTO] = [], outgoing: [FriendEntryDTO] = []) {
        self.incoming = incoming
        self.outgoing = outgoing
    }
}

public struct FriendRequestCreateDTO: Codable, Equatable, Sendable {
    public var username: String?
    public var userId: String?

    public init(username: String? = nil, userId: String? = nil) {
        self.username = username
        self.userId = userId
    }

    enum CodingKeys: String, CodingKey {
        case username
        case userId = "user_id"
    }
}

public struct FriendRequestResponseDTO: Codable, Equatable, Sendable {
    public var created: Bool?
    public var friendship: FriendshipDTO

    public init(created: Bool? = nil, friendship: FriendshipDTO) {
        self.created = created
        self.friendship = friendship
    }
}

public struct FriendshipActionRequest: Codable, Equatable, Sendable {
    public var friendshipId: String?
    public var userId: String?

    public init(friendshipId: String? = nil, userId: String? = nil) {
        self.friendshipId = friendshipId
        self.userId = userId
    }
}

public struct FriendshipActionResponseDTO: Codable, Equatable, Sendable {
    public var removed: Bool?
    public var friendshipId: String?
    public var friendship: FriendshipDTO?

    public init(removed: Bool? = nil, friendshipId: String? = nil, friendship: FriendshipDTO? = nil) {
        self.removed = removed
        self.friendshipId = friendshipId
        self.friendship = friendship
    }
}

public struct FriendFeedDailyMetricDTO: Codable, Equatable, Sendable {
    public var day: String
    public var recovery: Double?
    public var effort: Double?
    public var totalSleepMin: Double?
    public var restingHr: Int?
    public var avgHrv: Double?
    public var steps: Int?

    public init(
        day: String,
        recovery: Double? = nil,
        effort: Double? = nil,
        totalSleepMin: Double? = nil,
        restingHr: Int? = nil,
        avgHrv: Double? = nil,
        steps: Int? = nil
    ) {
        self.day = day
        self.recovery = recovery
        self.effort = effort
        self.totalSleepMin = totalSleepMin
        self.restingHr = restingHr
        self.avgHrv = avgHrv
        self.steps = steps
    }
}

public struct FriendFeedSleepSessionDTO: Codable, Equatable, Sendable {
    public var startTs: Int?
    public var endTs: Int?
    public var totalSleepMin: Double?
    public var efficiency: Double?

    public init(startTs: Int? = nil, endTs: Int? = nil, totalSleepMin: Double? = nil, efficiency: Double? = nil) {
        self.startTs = startTs
        self.endTs = endTs
        self.totalSleepMin = totalSleepMin
        self.efficiency = efficiency
    }
}

public struct FriendFeedWorkoutDTO: Codable, Equatable, Sendable, Identifiable {
    public var startTs: Int?
    public var endTs: Int?
    public var sport: String?
    public var effort: Double?
    public var calories: Double?

    public var id: String { "\(startTs ?? 0)-\(sport ?? "workout")" }

    public init(startTs: Int? = nil, endTs: Int? = nil, sport: String? = nil, effort: Double? = nil, calories: Double? = nil) {
        self.startTs = startTs
        self.endTs = endTs
        self.sport = sport
        self.effort = effort
        self.calories = calories
    }
}

public struct FriendFeedMetricSeriesDTO: Codable, Equatable, Sendable, Identifiable {
    public var day: String
    public var key: String
    public var value: Double

    public var id: String { "\(day)-\(key)" }

    public init(day: String, key: String, value: Double) {
        self.day = day
        self.key = key
        self.value = value
    }
}

public struct FriendFeedEntryDTO: Codable, Equatable, Sendable, Identifiable {
    public var user: CloudUserDTO
    public var latestDailyMetric: FriendFeedDailyMetricDTO?
    public var latestSleepSession: FriendFeedSleepSessionDTO?
    public var recentWorkouts: [FriendFeedWorkoutDTO]
    public var metricSeries: [FriendFeedMetricSeriesDTO]

    public var id: String { user.id }

    public init(
        user: CloudUserDTO,
        latestDailyMetric: FriendFeedDailyMetricDTO? = nil,
        latestSleepSession: FriendFeedSleepSessionDTO? = nil,
        recentWorkouts: [FriendFeedWorkoutDTO] = [],
        metricSeries: [FriendFeedMetricSeriesDTO] = []
    ) {
        self.user = user
        self.latestDailyMetric = latestDailyMetric
        self.latestSleepSession = latestSleepSession
        self.recentWorkouts = recentWorkouts
        self.metricSeries = metricSeries
    }
}

public struct FriendsFeedDTO: Codable, Equatable, Sendable {
    public var friends: [FriendFeedEntryDTO]

    public init(friends: [FriendFeedEntryDTO] = []) {
        self.friends = friends
    }
}

public struct CloudAPIErrorDTO: Codable, Equatable, Sendable {
    public var error: String
    public var detail: String?

    public init(error: String, detail: String? = nil) {
        self.error = error
        self.detail = detail
    }
}

private struct EmptyResponse: Codable {}

public protocol FriendsClient: Sendable {
    func signup(_ request: CloudAuthRequest, identity: CloudDeviceIdentity?, config: CloudConfig) async throws -> CloudAuthResponseDTO
    func login(_ request: CloudAuthRequest, identity: CloudDeviceIdentity?, config: CloudConfig) async throws -> CloudAuthResponseDTO
    func logout(session: CloudAuthSession, config: CloudConfig) async throws
    func userMe(session: CloudAuthSession, config: CloudConfig) async throws -> CloudUserMeDTO
    func updateUser(_ profile: CloudUserProfileRequest, session: CloudAuthSession, config: CloudConfig) async throws -> CloudUserMeDTO
    func updatePrivacy(_ privacy: CloudUserPrivacyRequest, session: CloudAuthSession, config: CloudConfig) async throws -> CloudUserMeDTO
    func requestFriend(_ request: FriendRequestCreateDTO, session: CloudAuthSession, config: CloudConfig) async throws -> FriendRequestResponseDTO
    func acceptFriendship(_ request: FriendshipActionRequest, session: CloudAuthSession, config: CloudConfig) async throws -> FriendshipActionResponseDTO
    func rejectFriendship(_ request: FriendshipActionRequest, session: CloudAuthSession, config: CloudConfig) async throws -> FriendshipActionResponseDTO
    func removeFriendship(_ request: FriendshipActionRequest, session: CloudAuthSession, config: CloudConfig) async throws -> FriendshipActionResponseDTO
    func friends(session: CloudAuthSession, config: CloudConfig) async throws -> FriendsListDTO
    func friendRequests(session: CloudAuthSession, config: CloudConfig) async throws -> FriendRequestsDTO
    func feed(session: CloudAuthSession, config: CloudConfig) async throws -> FriendsFeedDTO

    func summary(identity: CloudDeviceIdentity, config: CloudConfig) async throws -> FriendsSummaryDTO
    func bootstrapUser(_ profile: CloudUserProfileRequest, identity: CloudDeviceIdentity, config: CloudConfig) async throws -> CloudUserMeDTO
    func userMe(identity: CloudDeviceIdentity, config: CloudConfig) async throws -> CloudUserMeDTO
    func updateUser(_ profile: CloudUserProfileRequest, identity: CloudDeviceIdentity, config: CloudConfig) async throws -> CloudUserMeDTO
    func updatePrivacy(_ privacy: CloudUserPrivacyRequest, identity: CloudDeviceIdentity, config: CloudConfig) async throws -> CloudUserMeDTO
    func requestFriend(_ request: FriendRequestCreateDTO, identity: CloudDeviceIdentity, config: CloudConfig) async throws -> FriendRequestResponseDTO
    func acceptFriendship(_ request: FriendshipActionRequest, identity: CloudDeviceIdentity, config: CloudConfig) async throws -> FriendshipActionResponseDTO
    func rejectFriendship(_ request: FriendshipActionRequest, identity: CloudDeviceIdentity, config: CloudConfig) async throws -> FriendshipActionResponseDTO
    func removeFriendship(_ request: FriendshipActionRequest, identity: CloudDeviceIdentity, config: CloudConfig) async throws -> FriendshipActionResponseDTO
    func friends(identity: CloudDeviceIdentity, config: CloudConfig) async throws -> FriendsListDTO
    func friendRequests(identity: CloudDeviceIdentity, config: CloudConfig) async throws -> FriendRequestsDTO
    func feed(identity: CloudDeviceIdentity, config: CloudConfig) async throws -> FriendsFeedDTO
}

public struct DisabledFriendsClient: FriendsClient {
    public init() {}

    public func signup(_ request: CloudAuthRequest, identity: CloudDeviceIdentity?, config: CloudConfig) async throws -> CloudAuthResponseDTO {
        _ = request
        _ = identity
        _ = config
        throw APIClientError.disabled
    }

    public func login(_ request: CloudAuthRequest, identity: CloudDeviceIdentity?, config: CloudConfig) async throws -> CloudAuthResponseDTO {
        _ = request
        _ = identity
        _ = config
        throw APIClientError.disabled
    }

    public func logout(session: CloudAuthSession, config: CloudConfig) async throws {
        _ = session
        _ = config
        throw APIClientError.disabled
    }

    public func userMe(session: CloudAuthSession, config: CloudConfig) async throws -> CloudUserMeDTO {
        _ = session
        _ = config
        throw APIClientError.disabled
    }

    public func updateUser(_ profile: CloudUserProfileRequest, session: CloudAuthSession, config: CloudConfig) async throws -> CloudUserMeDTO {
        _ = profile
        _ = session
        _ = config
        throw APIClientError.disabled
    }

    public func updatePrivacy(_ privacy: CloudUserPrivacyRequest, session: CloudAuthSession, config: CloudConfig) async throws -> CloudUserMeDTO {
        _ = privacy
        _ = session
        _ = config
        throw APIClientError.disabled
    }

    public func requestFriend(_ request: FriendRequestCreateDTO, session: CloudAuthSession, config: CloudConfig) async throws -> FriendRequestResponseDTO {
        _ = request
        _ = session
        _ = config
        throw APIClientError.disabled
    }

    public func acceptFriendship(_ request: FriendshipActionRequest, session: CloudAuthSession, config: CloudConfig) async throws -> FriendshipActionResponseDTO {
        _ = request
        _ = session
        _ = config
        throw APIClientError.disabled
    }

    public func rejectFriendship(_ request: FriendshipActionRequest, session: CloudAuthSession, config: CloudConfig) async throws -> FriendshipActionResponseDTO {
        _ = request
        _ = session
        _ = config
        throw APIClientError.disabled
    }

    public func removeFriendship(_ request: FriendshipActionRequest, session: CloudAuthSession, config: CloudConfig) async throws -> FriendshipActionResponseDTO {
        _ = request
        _ = session
        _ = config
        throw APIClientError.disabled
    }

    public func friends(session: CloudAuthSession, config: CloudConfig) async throws -> FriendsListDTO {
        _ = session
        _ = config
        throw APIClientError.disabled
    }

    public func friendRequests(session: CloudAuthSession, config: CloudConfig) async throws -> FriendRequestsDTO {
        _ = session
        _ = config
        throw APIClientError.disabled
    }

    public func feed(session: CloudAuthSession, config: CloudConfig) async throws -> FriendsFeedDTO {
        _ = session
        _ = config
        throw APIClientError.disabled
    }

    public func summary(identity: CloudDeviceIdentity, config: CloudConfig) async throws -> FriendsSummaryDTO {
        _ = identity
        _ = config
        return FriendsSummaryDTO()
    }

    public func bootstrapUser(_ profile: CloudUserProfileRequest, identity: CloudDeviceIdentity, config: CloudConfig) async throws -> CloudUserMeDTO {
        _ = profile
        _ = identity
        _ = config
        throw APIClientError.disabled
    }

    public func userMe(identity: CloudDeviceIdentity, config: CloudConfig) async throws -> CloudUserMeDTO {
        _ = identity
        _ = config
        throw APIClientError.disabled
    }

    public func updateUser(_ profile: CloudUserProfileRequest, identity: CloudDeviceIdentity, config: CloudConfig) async throws -> CloudUserMeDTO {
        _ = profile
        _ = identity
        _ = config
        throw APIClientError.disabled
    }

    public func updatePrivacy(_ privacy: CloudUserPrivacyRequest, identity: CloudDeviceIdentity, config: CloudConfig) async throws -> CloudUserMeDTO {
        _ = privacy
        _ = identity
        _ = config
        throw APIClientError.disabled
    }

    public func requestFriend(_ request: FriendRequestCreateDTO, identity: CloudDeviceIdentity, config: CloudConfig) async throws -> FriendRequestResponseDTO {
        _ = request
        _ = identity
        _ = config
        throw APIClientError.disabled
    }

    public func acceptFriendship(_ request: FriendshipActionRequest, identity: CloudDeviceIdentity, config: CloudConfig) async throws -> FriendshipActionResponseDTO {
        _ = request
        _ = identity
        _ = config
        throw APIClientError.disabled
    }

    public func rejectFriendship(_ request: FriendshipActionRequest, identity: CloudDeviceIdentity, config: CloudConfig) async throws -> FriendshipActionResponseDTO {
        _ = request
        _ = identity
        _ = config
        throw APIClientError.disabled
    }

    public func removeFriendship(_ request: FriendshipActionRequest, identity: CloudDeviceIdentity, config: CloudConfig) async throws -> FriendshipActionResponseDTO {
        _ = request
        _ = identity
        _ = config
        throw APIClientError.disabled
    }

    public func friends(identity: CloudDeviceIdentity, config: CloudConfig) async throws -> FriendsListDTO {
        _ = identity
        _ = config
        throw APIClientError.disabled
    }

    public func friendRequests(identity: CloudDeviceIdentity, config: CloudConfig) async throws -> FriendRequestsDTO {
        _ = identity
        _ = config
        throw APIClientError.disabled
    }

    public func feed(identity: CloudDeviceIdentity, config: CloudConfig) async throws -> FriendsFeedDTO {
        _ = identity
        _ = config
        throw APIClientError.disabled
    }
}

public struct HTTPFriendsClient: FriendsClient {
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

    public func signup(_ request: CloudAuthRequest, identity: CloudDeviceIdentity?, config: CloudConfig) async throws -> CloudAuthResponseDTO {
        try await send(path: "v1/auth/signup", method: "POST", body: request, bearerToken: identity?.deviceToken, config: config)
    }

    public func login(_ request: CloudAuthRequest, identity: CloudDeviceIdentity?, config: CloudConfig) async throws -> CloudAuthResponseDTO {
        try await send(path: "v1/auth/login", method: "POST", body: request, bearerToken: identity?.deviceToken, config: config)
    }

    public func logout(session: CloudAuthSession, config: CloudConfig) async throws {
        let _: EmptyResponse = try await send(path: "v1/auth/logout", method: "POST", bearerToken: session.token, config: config)
    }

    public func userMe(session: CloudAuthSession, config: CloudConfig) async throws -> CloudUserMeDTO {
        try await send(path: "v1/user/me", method: "GET", bearerToken: session.token, config: config)
    }

    public func updateUser(_ profile: CloudUserProfileRequest, session: CloudAuthSession, config: CloudConfig) async throws -> CloudUserMeDTO {
        try await send(path: "v1/user/me", method: "PATCH", body: profile, bearerToken: session.token, config: config)
    }

    public func updatePrivacy(_ privacy: CloudUserPrivacyRequest, session: CloudAuthSession, config: CloudConfig) async throws -> CloudUserMeDTO {
        try await send(path: "v1/user/privacy", method: "PATCH", body: privacy, bearerToken: session.token, config: config)
    }

    public func requestFriend(_ request: FriendRequestCreateDTO, session: CloudAuthSession, config: CloudConfig) async throws -> FriendRequestResponseDTO {
        logDebugBody("POST", path: "v1/friends/request", body: request)
        return try await send(path: "v1/friends/request", method: "POST", body: request, bearerToken: session.token, config: config)
    }

    public func acceptFriendship(_ request: FriendshipActionRequest, session: CloudAuthSession, config: CloudConfig) async throws -> FriendshipActionResponseDTO {
        try await send(path: "v1/friends/accept", method: "POST", body: request, bearerToken: session.token, config: config)
    }

    public func rejectFriendship(_ request: FriendshipActionRequest, session: CloudAuthSession, config: CloudConfig) async throws -> FriendshipActionResponseDTO {
        try await send(path: "v1/friends/reject", method: "POST", body: request, bearerToken: session.token, config: config)
    }

    public func removeFriendship(_ request: FriendshipActionRequest, session: CloudAuthSession, config: CloudConfig) async throws -> FriendshipActionResponseDTO {
        try await send(path: "v1/friends/remove", method: "POST", body: request, bearerToken: session.token, config: config)
    }

    public func friends(session: CloudAuthSession, config: CloudConfig) async throws -> FriendsListDTO {
        try await send(path: "v1/friends", method: "GET", bearerToken: session.token, config: config)
    }

    public func friendRequests(session: CloudAuthSession, config: CloudConfig) async throws -> FriendRequestsDTO {
        try await send(path: "v1/friends/requests", method: "GET", bearerToken: session.token, config: config)
    }

    public func feed(session: CloudAuthSession, config: CloudConfig) async throws -> FriendsFeedDTO {
        try await send(path: "v1/friends/feed", method: "GET", bearerToken: session.token, config: config)
    }

    public func summary(identity: CloudDeviceIdentity, config: CloudConfig) async throws -> FriendsSummaryDTO {
        try await send(path: "v1/friends/summary", method: "GET", identity: identity, config: config)
    }

    public func bootstrapUser(_ profile: CloudUserProfileRequest, identity: CloudDeviceIdentity, config: CloudConfig) async throws -> CloudUserMeDTO {
        try await send(path: "v1/user/bootstrap", method: "POST", body: profile, identity: identity, config: config)
    }

    public func userMe(identity: CloudDeviceIdentity, config: CloudConfig) async throws -> CloudUserMeDTO {
        try await send(path: "v1/user/me", method: "GET", identity: identity, config: config)
    }

    public func updateUser(_ profile: CloudUserProfileRequest, identity: CloudDeviceIdentity, config: CloudConfig) async throws -> CloudUserMeDTO {
        try await send(path: "v1/user/me", method: "PATCH", body: profile, identity: identity, config: config)
    }

    public func updatePrivacy(_ privacy: CloudUserPrivacyRequest, identity: CloudDeviceIdentity, config: CloudConfig) async throws -> CloudUserMeDTO {
        try await send(path: "v1/user/privacy", method: "PATCH", body: privacy, identity: identity, config: config)
    }

    public func requestFriend(_ request: FriendRequestCreateDTO, identity: CloudDeviceIdentity, config: CloudConfig) async throws -> FriendRequestResponseDTO {
        logDebugBody("POST", path: "v1/friends/request", body: request)
        return try await send(path: "v1/friends/request", method: "POST", body: request, identity: identity, config: config)
    }

    public func acceptFriendship(_ request: FriendshipActionRequest, identity: CloudDeviceIdentity, config: CloudConfig) async throws -> FriendshipActionResponseDTO {
        try await send(path: "v1/friends/accept", method: "POST", body: request, identity: identity, config: config)
    }

    public func rejectFriendship(_ request: FriendshipActionRequest, identity: CloudDeviceIdentity, config: CloudConfig) async throws -> FriendshipActionResponseDTO {
        try await send(path: "v1/friends/reject", method: "POST", body: request, identity: identity, config: config)
    }

    public func removeFriendship(_ request: FriendshipActionRequest, identity: CloudDeviceIdentity, config: CloudConfig) async throws -> FriendshipActionResponseDTO {
        try await send(path: "v1/friends/remove", method: "POST", body: request, identity: identity, config: config)
    }

    public func friends(identity: CloudDeviceIdentity, config: CloudConfig) async throws -> FriendsListDTO {
        try await send(path: "v1/friends", method: "GET", identity: identity, config: config)
    }

    public func friendRequests(identity: CloudDeviceIdentity, config: CloudConfig) async throws -> FriendRequestsDTO {
        try await send(path: "v1/friends/requests", method: "GET", identity: identity, config: config)
    }

    public func feed(identity: CloudDeviceIdentity, config: CloudConfig) async throws -> FriendsFeedDTO {
        try await send(path: "v1/friends/feed", method: "GET", identity: identity, config: config)
    }

    private func send<Response: Decodable>(
        path: String,
        method: String,
        identity: CloudDeviceIdentity,
        config: CloudConfig
    ) async throws -> Response {
        let request = try makeRequest(path: path, method: method, identity: identity, config: config)
        return try await decodeResponse(request)
    }

    private func send<Response: Decodable>(
        path: String,
        method: String,
        bearerToken: String?,
        config: CloudConfig
    ) async throws -> Response {
        let request = try makeRequest(path: path, method: method, bearerToken: bearerToken, config: config)
        return try await decodeResponse(request)
    }

    private func send<Body: Encodable, Response: Decodable>(
        path: String,
        method: String,
        body: Body,
        identity: CloudDeviceIdentity,
        config: CloudConfig
    ) async throws -> Response {
        var request = try makeRequest(path: path, method: method, identity: identity, config: config)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try encoder.encode(body)
        return try await decodeResponse(request)
    }

    private func send<Body: Encodable, Response: Decodable>(
        path: String,
        method: String,
        body: Body,
        bearerToken: String?,
        config: CloudConfig
    ) async throws -> Response {
        var request = try makeRequest(path: path, method: method, bearerToken: bearerToken, config: config)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try encoder.encode(body)
        return try await decodeResponse(request)
    }

    private func logDebugBody<Body: Encodable>(_ method: String, path: String, body: Body) {
        #if DEBUG
        guard let data = try? encoder.encode(body),
              let json = String(data: data, encoding: .utf8) else { return }
        print("[NoopCloudSync] \(method) /\(path) body=\(json)")
        #endif
    }

    private func makeRequest(path: String, method: String, identity: CloudDeviceIdentity, config: CloudConfig) throws -> URLRequest {
        guard let serverURL = config.serverURL else { throw APIClientError.missingServerURL }
        guard let deviceToken = identity.deviceToken, !deviceToken.isEmpty else { throw APIClientError.missingDeviceToken }

        var request = URLRequest(url: serverURL.appendingPathComponent(path))
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(deviceToken)", forHTTPHeaderField: "Authorization")
        return request
    }

    private func makeRequest(path: String, method: String, bearerToken: String?, config: CloudConfig) throws -> URLRequest {
        guard let serverURL = config.serverURL else { throw APIClientError.missingServerURL }
        var request = URLRequest(url: serverURL.appendingPathComponent(path))
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let bearerToken, !bearerToken.isEmpty {
            request.setValue("Bearer \(bearerToken)", forHTTPHeaderField: "Authorization")
        }
        return request
    }

    private func decodeResponse<Response: Decodable>(_ request: URLRequest) async throws -> Response {
        let (data, response) = try await transport.data(for: request)
        guard (200..<300).contains(response.statusCode) else {
            if let error = try? decoder.decode(CloudAPIErrorDTO.self, from: data) {
                #if DEBUG
                print("[NoopCloudSync] \(request.httpMethod ?? "HTTP") \(request.url?.path ?? "") failed status=\(response.statusCode) error=\(error.error) detail=\(error.detail ?? "")")
                #endif
                throw CloudFriendsClientError.server(statusCode: response.statusCode, code: error.error, detail: error.detail)
            }
            #if DEBUG
            let rawBody = String(data: data, encoding: .utf8) ?? "<non-utf8 body>"
            print("[NoopCloudSync] \(request.httpMethod ?? "HTTP") \(request.url?.path ?? "") failed status=\(response.statusCode) body=\(rawBody)")
            #endif
            throw APIClientError.httpStatus(response.statusCode)
        }
        return try decoder.decode(Response.self, from: data)
    }
}

public enum CloudFriendsClientError: Error, Equatable, Sendable {
    case server(statusCode: Int, code: String, detail: String?)
}

extension CloudFriendsClientError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case let .server(statusCode, code, detail):
            switch code {
            case "invalid_credentials":
                return "Username or password is incorrect."
            case "invalid_auth_request":
                return detail ?? "Check your username and password."
            case "username_conflict":
                return "That username is already taken."
            case "user_not_bootstrapped":
                return "Create your Cloud profile before using Friends."
            case "friend_not_found":
                return "User not found."
            case "cannot_friend_self":
                return "You cannot add yourself as a friend."
            case "friendship_not_found":
                return "That friend request is no longer available."
            default:
                if let detail, !detail.isEmpty { return detail }
                return "Cloud request failed (\(statusCode): \(code))."
            }
        }
    }
}
