import Foundation
import Security

public actor KeychainAuthSessionStore {
    private let service: String
    private let account: String

    public init(service: String = "com.noop.cloud.sync", account: String = "auth-session") {
        self.service = service
        self.account = account
    }

    public func loadSession() async throws -> CloudAuthSession? {
        var query = baseQuery()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status != errSecItemNotFound else { return nil }
        guard status == errSecSuccess else { throw KeychainAuthSessionStoreError.loadFailed(status) }
        guard let data = result as? Data,
              let token = String(data: data, encoding: .utf8),
              !token.isEmpty else {
            throw KeychainAuthSessionStoreError.unexpectedPayload
        }
        return CloudAuthSession(token: token)
    }

    public func saveSession(_ session: CloudAuthSession) async throws {
        let data = Data(session.token.utf8)
        let query = baseQuery()
        SecItemDelete(query as CFDictionary)

        var attributes = query
        attributes[kSecValueData as String] = data
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly

        let status = SecItemAdd(attributes as CFDictionary, nil)
        guard status == errSecSuccess else { throw KeychainAuthSessionStoreError.saveFailed(status) }
    }

    public func clearSession() async throws {
        let status = SecItemDelete(baseQuery() as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainAuthSessionStoreError.deleteFailed(status)
        }
    }

    private func baseQuery() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }
}

public enum KeychainAuthSessionStoreError: Error, Equatable, Sendable {
    case loadFailed(OSStatus)
    case saveFailed(OSStatus)
    case deleteFailed(OSStatus)
    case unexpectedPayload
}
