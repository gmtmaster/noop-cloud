#if os(iOS)
import Foundation
import NoopCloudSync

enum CloudUserSession {
    static let didChangeNotification = Notification.Name("noop.cloud.userSession.didChange")

    static let userIdKey = "noop.cloud.user.id"
    static let usernameKey = "noop.cloud.user.username"
    static let displayNameKey = "noop.cloud.user.displayName"
    static let avatarURLKey = "noop.cloud.user.avatarURL"
    static let shareRecoveryKey = "noop.cloud.user.shareRecovery"
    static let shareSleepKey = "noop.cloud.user.shareSleep"
    static let shareWorkoutsKey = "noop.cloud.user.shareWorkouts"
    static let shareDailyEffortKey = "noop.cloud.user.shareDailyEffort"
    static let lastRestoreAtKey = "noop.cloud.user.lastRestoreAt"

    static func isLoggedIn(defaults: UserDefaults = .standard) -> Bool {
        !(defaults.string(forKey: userIdKey) ?? "").isEmpty
    }

    static func cachedUser(defaults: UserDefaults = .standard) -> CloudUserDTO? {
        guard let id = defaults.string(forKey: userIdKey), !id.isEmpty else { return nil }
        return CloudUserDTO(
            id: id,
            username: nilIfEmpty(defaults.string(forKey: usernameKey)),
            displayName: nilIfEmpty(defaults.string(forKey: displayNameKey)),
            avatarUrl: nilIfEmpty(defaults.string(forKey: avatarURLKey)),
            shareRecovery: bool(defaults, shareRecoveryKey, defaultValue: true),
            shareSleep: bool(defaults, shareSleepKey, defaultValue: true),
            shareWorkouts: bool(defaults, shareWorkoutsKey, defaultValue: true),
            shareDailyEffort: bool(defaults, shareDailyEffortKey, defaultValue: true)
        )
    }

    static func save(_ user: CloudUserDTO, defaults: UserDefaults = .standard) {
        let changed =
            defaults.string(forKey: userIdKey) != user.id ||
            defaults.string(forKey: usernameKey) != (user.username ?? "") ||
            defaults.string(forKey: displayNameKey) != (user.displayName ?? "") ||
            defaults.string(forKey: avatarURLKey) != (user.avatarUrl ?? "") ||
            bool(defaults, shareRecoveryKey, defaultValue: true) != (user.shareRecovery ?? true) ||
            bool(defaults, shareSleepKey, defaultValue: true) != (user.shareSleep ?? true) ||
            bool(defaults, shareWorkoutsKey, defaultValue: true) != (user.shareWorkouts ?? true) ||
            bool(defaults, shareDailyEffortKey, defaultValue: true) != (user.shareDailyEffort ?? true)

        defaults.set(user.id, forKey: userIdKey)
        defaults.set(user.username ?? "", forKey: usernameKey)
        defaults.set(user.displayName ?? "", forKey: displayNameKey)
        defaults.set(user.avatarUrl ?? "", forKey: avatarURLKey)
        defaults.set(user.shareRecovery ?? true, forKey: shareRecoveryKey)
        defaults.set(user.shareSleep ?? true, forKey: shareSleepKey)
        defaults.set(user.shareWorkouts ?? true, forKey: shareWorkoutsKey)
        defaults.set(user.shareDailyEffort ?? true, forKey: shareDailyEffortKey)
        defaults.set(Date().timeIntervalSince1970, forKey: lastRestoreAtKey)
        if changed { notifyDidChange() }
    }

    static func clear(defaults: UserDefaults = .standard) {
        let changed = isLoggedIn(defaults: defaults) || defaults.bool(forKey: CloudSyncPreferences.enabledKey)
        [
            userIdKey, usernameKey, displayNameKey, avatarURLKey,
            shareRecoveryKey, shareSleepKey, shareWorkoutsKey, shareDailyEffortKey,
            lastRestoreAtKey
        ].forEach { defaults.removeObject(forKey: $0) }
        defaults.set(false, forKey: CloudSyncPreferences.enabledKey)
        if changed { notifyDidChange() }
    }

    static func saveSession(_ token: String, store: KeychainAuthSessionStore = KeychainAuthSessionStore()) async throws {
        try await store.saveSession(CloudAuthSession(token: token))
        notifyDidChange()
    }

    static func loadSession(store: KeychainAuthSessionStore = KeychainAuthSessionStore()) async throws -> CloudAuthSession? {
        try await store.loadSession()
    }

    static func clearSession(store: KeychainAuthSessionStore = KeychainAuthSessionStore()) async {
        try? await store.clearSession()
        clear()
    }

    @discardableResult
    static func restoreIfPossible(
        identityStore: IdentityStore = KeychainIdentityStore(),
        sessionStore: KeychainAuthSessionStore = KeychainAuthSessionStore(),
        client: FriendsClient = HTTPFriendsClient(),
        defaults: UserDefaults = .standard
    ) async -> CloudUserDTO? {
        let config = CloudSyncPreferences.connectionConfig(defaults: defaults)
        guard config.serverURL != nil else { return cachedUser(defaults: defaults) }

        do {
            if let session = try await sessionStore.loadSession() {
                let me = try await client.userMe(session: session, config: config)
                if let user = me.user {
                    save(user, defaults: defaults)
                    return user
                }
                try? await sessionStore.clearSession()
                clear(defaults: defaults)
                return nil
            }
            let identity = try await identityStore.loadIdentity()
            guard let identity, identity.isRegistered else { return cachedUser(defaults: defaults) }
            let me = try await client.userMe(identity: identity, config: config)
            if let user = me.user {
                save(user, defaults: defaults)
                return user
            }
            clear(defaults: defaults)
            return nil
        } catch {
            return cachedUser(defaults: defaults)
        }
    }

    private static func bool(_ defaults: UserDefaults, _ key: String, defaultValue: Bool) -> Bool {
        defaults.object(forKey: key) as? Bool ?? defaultValue
    }

    private static func nilIfEmpty(_ value: String?) -> String? {
        guard let value, !value.isEmpty else { return nil }
        return value
    }

    private static func notifyDidChange() {
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: didChangeNotification, object: nil)
        }
    }
}
#endif
