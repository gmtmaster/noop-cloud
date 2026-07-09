import Foundation

public struct CloudDeviceIdentity: Equatable, Sendable {
    public var cloudDeviceId: String?
    public var primaryNoopDeviceId: String
    public var deviceToken: String?
    public var displayName: String?

    public init(
        cloudDeviceId: String? = nil,
        primaryNoopDeviceId: String = "my-whoop",
        deviceToken: String? = nil,
        displayName: String? = nil
    ) {
        self.cloudDeviceId = cloudDeviceId
        self.primaryNoopDeviceId = primaryNoopDeviceId
        self.deviceToken = deviceToken
        self.displayName = displayName
    }

    public var isRegistered: Bool {
        deviceToken?.isEmpty == false
    }
}

public protocol IdentityStore: Sendable {
    func loadIdentity() async throws -> CloudDeviceIdentity?
    func saveIdentity(_ identity: CloudDeviceIdentity) async throws
    func clearIdentity() async throws
}

/// Phase-1 identity store. It intentionally persists nothing; secure token generation/storage belongs
/// to the backend-communication phase.
public actor DisabledIdentityStore: IdentityStore {
    public init() {}

    public func loadIdentity() async throws -> CloudDeviceIdentity? {
        nil
    }

    public func saveIdentity(_ identity: CloudDeviceIdentity) async throws {
        _ = identity
    }

    public func clearIdentity() async throws {}
}

