import Foundation
import Security

public actor KeychainIdentityStore: IdentityStore {
    private let service: String
    private let account: String

    public init(service: String = "com.noop.cloud.sync", account: String = "device-identity") {
        self.service = service
        self.account = account
    }

    public func loadIdentity() async throws -> CloudDeviceIdentity? {
        if let stored = try readStoredIdentity() {
            return stored
        }

        let identity = CloudDeviceIdentity(
            cloudDeviceId: UUID().uuidString,
            primaryNoopDeviceId: "my-whoop",
            deviceToken: try DeviceTokenGenerator.makeToken()
        )
        try await saveIdentity(identity)
        return identity
    }

    public func saveIdentity(_ identity: CloudDeviceIdentity) async throws {
        let data = try JSONEncoder().encode(StoredCloudDeviceIdentity(identity))
        let query = baseQuery()
        SecItemDelete(query as CFDictionary)

        var attributes = query
        attributes[kSecValueData as String] = data
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly

        let status = SecItemAdd(attributes as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainIdentityStoreError.saveFailed(status)
        }
    }

    public func clearIdentity() async throws {
        let status = SecItemDelete(baseQuery() as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainIdentityStoreError.deleteFailed(status)
        }
    }

    private func readStoredIdentity() throws -> CloudDeviceIdentity? {
        var query = baseQuery()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status != errSecItemNotFound else { return nil }
        guard status == errSecSuccess else {
            throw KeychainIdentityStoreError.loadFailed(status)
        }
        guard let data = result as? Data else {
            throw KeychainIdentityStoreError.unexpectedPayload
        }

        return try JSONDecoder().decode(StoredCloudDeviceIdentity.self, from: data).identity
    }

    private func baseQuery() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }
}

public enum KeychainIdentityStoreError: Error, Equatable, Sendable {
    case loadFailed(OSStatus)
    case saveFailed(OSStatus)
    case deleteFailed(OSStatus)
    case unexpectedPayload
}

private struct StoredCloudDeviceIdentity: Codable {
    var cloudDeviceId: String?
    var primaryNoopDeviceId: String
    var deviceToken: String?
    var displayName: String?

    init(_ identity: CloudDeviceIdentity) {
        cloudDeviceId = identity.cloudDeviceId
        primaryNoopDeviceId = identity.primaryNoopDeviceId
        deviceToken = identity.deviceToken
        displayName = identity.displayName
    }

    var identity: CloudDeviceIdentity {
        CloudDeviceIdentity(
            cloudDeviceId: cloudDeviceId,
            primaryNoopDeviceId: primaryNoopDeviceId,
            deviceToken: deviceToken,
            displayName: displayName
        )
    }
}
