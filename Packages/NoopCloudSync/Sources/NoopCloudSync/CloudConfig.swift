import Foundation

/// Configuration for the fork-side NOOP Cloud pipeline.
///
/// Phase 1 deliberately defaults to disabled and performs no network or database work. Later phases can
/// load this from Settings/UserDefaults once the user has explicitly opted in.
public struct CloudConfig: Equatable, Sendable {
    public var isEnabled: Bool
    public var serverURL: URL?
    public var uploadWindowDays: Int
    public var schemaVersion: String
    public var appVersion: String?

    public init(
        isEnabled: Bool = false,
        serverURL: URL? = nil,
        uploadWindowDays: Int = 30,
        schemaVersion: String = "noop-cloud-sync-v1",
        appVersion: String? = nil
    ) {
        self.isEnabled = isEnabled
        self.serverURL = serverURL
        self.uploadWindowDays = uploadWindowDays
        self.schemaVersion = schemaVersion
        self.appVersion = appVersion
    }

    public static let disabled = CloudConfig()
}

public protocol CloudConfigProviding: Sendable {
    func loadCloudConfig() async -> CloudConfig
}

public struct StaticCloudConfigProvider: CloudConfigProviding {
    private let config: CloudConfig

    public init(config: CloudConfig = .disabled) {
        self.config = config
    }

    public func loadCloudConfig() async -> CloudConfig {
        config
    }
}
