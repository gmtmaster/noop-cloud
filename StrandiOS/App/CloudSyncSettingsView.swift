#if os(iOS)
import SwiftUI
import StrandDesign
import NoopCloudSync

struct CloudSyncSettingsView: View {
    @AppStorage(CloudSyncPreferences.enabledKey) private var enabled = false
    @AppStorage(CloudSyncPreferences.serverURLKey) private var serverURL = ""
    @AppStorage(CloudSyncPreferences.intervalMinutesKey) private var intervalMinutes = 0
    @AppStorage(CloudSyncPreferences.lastStatusKey) private var lastStatus = "Never synced"
    @AppStorage(CloudSyncPreferences.lastSuccessAtKey) private var lastSuccessAt = 0.0
    @StateObject private var model = CloudSyncSettingsModel()

    var body: some View {
        ScreenScaffold(title: "Cloud Sync", subtitle: "Read-only upload for your derived Noop data.") {
            if !model.hasCloudUser {
                loginRequiredCard
            }
            settingsCard
            statusCard
        }
        .task { await model.load() }
    }

    private var loginRequiredCard: some View {
        StrandCard(padding: 18, tint: StrandPalette.metricRose) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "person.crop.circle.badge.exclamationmark")
                    .foregroundStyle(StrandPalette.metricRose)
                VStack(alignment: .leading, spacing: 6) {
                    Text("Cloud profile required")
                        .font(StrandFont.headline)
                        .foregroundStyle(StrandPalette.textPrimary)
                    Text(CloudSyncPreferences.loginRequiredMessage)
                        .font(StrandFont.caption)
                        .foregroundStyle(StrandPalette.textSecondary)
                }
            }
        }
    }

    private var settingsCard: some View {
        StrandCard(padding: 20, tint: enabled ? StrandPalette.accent : nil) {
            VStack(alignment: .leading, spacing: 16) {
                Toggle(isOn: enableBinding) {
                    Text("Enable Cloud Sync")
                        .font(StrandFont.headline)
                        .foregroundStyle(StrandPalette.textPrimary)
                }
                .toggleStyle(.switch)
                .tint(StrandPalette.accent)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Server URL").strandOverline()
                    TextField("https://xxxxx.ngrok-free.app", text: $serverURL)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                        .autocorrectionDisabled()
                        .font(StrandFont.body)
                        .padding(12)
                        .background(RoundedRectangle(cornerRadius: 10).fill(StrandPalette.surfaceInset))
                        .foregroundStyle(StrandPalette.textPrimary)
                }

                Picker("Sync interval", selection: $intervalMinutes) {
                    ForEach(CloudSyncInterval.allCases) { interval in
                        Text(interval.label).tag(interval.rawValue)
                    }
                }
                .pickerStyle(.menu)
                .tint(StrandPalette.accent)

                Button {
                    Task { await model.testConnection(serverURL: serverURL) }
                } label: {
                    HStack {
                        if model.isTestingConnection { ProgressView().tint(StrandPalette.accent) }
                        Text(model.isTestingConnection ? "Testing" : "Test Connection")
                            .font(StrandFont.headline)
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(StrandPalette.accent)
                .disabled(model.isTestingConnection || URL(string: serverURL.trimmingCharacters(in: .whitespacesAndNewlines)) == nil)

                HStack(spacing: 10) {
                    Image(systemName: "key.fill")
                        .foregroundStyle(StrandPalette.accent)
                    Text(model.tokenPreview)
                        .font(StrandFont.caption)
                        .foregroundStyle(StrandPalette.textSecondary)
                    Spacer()
                    Button("Regenerate") {
                        Task { await model.regenerateToken() }
                    }
                    .font(StrandFont.caption)
                    .foregroundStyle(StrandPalette.accent)
                }

                Button {
                    Task { await model.syncNow(enabled: enabled, serverURL: serverURL) }
                } label: {
                    HStack {
                        if model.isSyncing { ProgressView().tint(StrandPalette.accent) }
                        Text(model.isSyncing ? "Syncing" : "Sync Now")
                            .font(StrandFont.headline)
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(StrandPalette.accent)
                .disabled(model.isSyncing || !model.hasCloudUser || !enabled || URL(string: serverURL.trimmingCharacters(in: .whitespacesAndNewlines)) == nil)
            }
        }
    }

    private var enableBinding: Binding<Bool> {
        Binding(
            get: { enabled && model.hasCloudUser },
            set: { newValue in
                if newValue && !model.hasCloudUser {
                    enabled = false
                    model.showLoginRequired()
                } else {
                    enabled = newValue
                    CloudSyncPreferences.setEnabled(newValue)
                }
            }
        )
    }

    private var statusCard: some View {
        StrandCard(padding: 20) {
            VStack(alignment: .leading, spacing: 10) {
                Text("LAST SYNC").strandOverline()
                Text(model.statusOverride ?? lastStatus)
                    .font(StrandFont.headline)
                    .foregroundStyle(model.statusTone)
                if lastSuccessAt > 0 {
                    Text(Date(timeIntervalSince1970: lastSuccessAt).formatted(date: .abbreviated, time: .shortened))
                        .font(StrandFont.caption)
                        .foregroundStyle(StrandPalette.textTertiary)
                }
                if let counts = model.lastCounts {
                    Text(counts)
                        .font(StrandFont.caption)
                        .foregroundStyle(StrandPalette.textSecondary)
                }
            }
        }
    }
}

@MainActor
private final class CloudSyncSettingsModel: ObservableObject {
    @Published var isSyncing = false
    @Published var isTestingConnection = false
    @Published var tokenPreview = "No token yet"
    @Published var statusOverride: String?
    @Published var lastCounts: String?
    @Published var statusTone: Color = StrandPalette.textSecondary
    @Published var hasCloudUser = CloudUserSession.isLoggedIn()

    private let identityStore = KeychainIdentityStore()

    func load() async {
        _ = await CloudUserSession.restoreIfPossible(identityStore: identityStore)
        hasCloudUser = CloudUserSession.isLoggedIn()
        if !hasCloudUser {
            UserDefaults.standard.set(false, forKey: CloudSyncPreferences.enabledKey)
        }
        await loadTokenPreview()
    }

    func showLoginRequired() {
        statusOverride = CloudSyncPreferences.loginRequiredMessage
        statusTone = StrandPalette.metricRose
    }

    func loadTokenPreview() async {
        do {
            let identity = try await identityStore.loadIdentity()
            tokenPreview = Self.preview(identity?.deviceToken)
        } catch {
            tokenPreview = "Token unavailable"
        }
    }

    func regenerateToken() async {
        do {
            try await identityStore.clearIdentity()
            let identity = try await identityStore.loadIdentity()
            tokenPreview = Self.preview(identity?.deviceToken)
        } catch {
            tokenPreview = "Reset failed"
        }
    }

    func testConnection(serverURL: String) async {
        let trimmed = serverURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let baseURL = URL(string: trimmed) else {
            statusOverride = "Enter a valid Cloud server URL."
            statusTone = StrandPalette.metricRose
            return
        }

        isTestingConnection = true
        statusOverride = "Testing connection"
        statusTone = StrandPalette.accent
        defer { isTestingConnection = false }

        do {
            let (data, response) = try await URLSession.shared.data(from: baseURL.appendingPathComponent("health"))
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                statusOverride = "Connection failed"
                statusTone = StrandPalette.metricRose
                return
            }
            let body = String(data: data, encoding: .utf8) ?? ""
            statusOverride = body.isEmpty ? "Connection OK" : "Connection OK"
            statusTone = StrandPalette.accent
        } catch {
            statusOverride = "Connection failed: \(error.localizedDescription)"
            statusTone = StrandPalette.metricRose
        }
    }

    func syncNow(enabled: Bool, serverURL: String) async {
        guard CloudUserSession.isLoggedIn() else {
            showLoginRequired()
            CloudSyncPreferences.saveFailure(CloudSyncPreferences.loginRequiredMessage)
            return
        }

        isSyncing = true
        statusOverride = "Syncing"
        statusTone = StrandPalette.accent
        defer { isSyncing = false }

        let trimmed = serverURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let config = CloudConfig(
            isEnabled: enabled,
            serverURL: URL(string: trimmed),
            uploadWindowDays: 30,
            schemaVersion: "noop-cloud-sync-v1",
            appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
        )

        do {
            let summary = try await CloudSyncRunner(identityStore: identityStore).syncNow(config: config)
            CloudSyncPreferences.saveSuccess(summary.response)
            statusOverride = "Success"
            statusTone = StrandPalette.accent
            lastCounts = "Accepted \(summary.response.acceptedDailyMetrics) daily, \(summary.response.acceptedSleepSessions) sleep, \(summary.response.acceptedWorkouts) workouts, \(summary.response.acceptedMetricSeries) series."
        } catch {
            CloudSyncPreferences.saveFailure(error.localizedDescription)
            statusOverride = "Failed: \(error.localizedDescription)"
            statusTone = StrandPalette.metricRose
        }
    }

    private static func preview(_ token: String?) -> String {
        guard let token, !token.isEmpty else { return "No token yet" }
        return "Bearer \(token.prefix(6))...\(token.suffix(4))"
    }
}
#endif
