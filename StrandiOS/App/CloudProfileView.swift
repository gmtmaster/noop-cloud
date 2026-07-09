#if os(iOS)
import SwiftUI
import StrandDesign
import NoopCloudSync

struct CloudProfileView: View {
    @StateObject private var model = CloudProfileViewModel()

    var body: some View {
        ScreenScaffold(title: "Profile", subtitle: model.user == nil ? "Log in or create your Cloud profile." : "Cloud profile and friend privacy.") {
            statusBanner

            if model.user == nil {
                authCard
            } else {
                profileCard
                privacyCard
                logoutCard
            }
        }
        .task { await model.load() }
    }

    @ViewBuilder
    private var statusBanner: some View {
        if model.isLoading {
            StrandCard(padding: 16) {
                HStack(spacing: 12) {
                    ProgressView().tint(StrandPalette.accent)
                    Text("Checking Cloud profile")
                        .font(StrandFont.body)
                        .foregroundStyle(StrandPalette.textSecondary)
                }
            }
        } else if let message = model.statusMessage {
            StrandCard(padding: 16, tint: model.isError ? StrandPalette.metricRose : StrandPalette.accent) {
                Text(message)
                    .font(StrandFont.caption)
                    .foregroundStyle(model.isError ? StrandPalette.metricRose : StrandPalette.textSecondary)
            }
        }
    }

    private var authCard: some View {
        StrandCard(padding: 20, tint: StrandPalette.accent) {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 14) {
                    avatar
                    VStack(alignment: .leading, spacing: 4) {
                        Text(model.authMode.title)
                            .font(StrandFont.headline)
                            .foregroundStyle(StrandPalette.textPrimary)
                        Text("Use your Cloud username and password for this server.")
                            .font(StrandFont.caption)
                            .foregroundStyle(StrandPalette.textTertiary)
                    }
                }

                Picker("Auth mode", selection: $model.authMode) {
                    ForEach(CloudAuthMode.allCases) { mode in
                        Text(mode.label).tag(mode)
                    }
                }
                .pickerStyle(.segmented)

                authFields

                Button {
                    Task { await model.submitAuth() }
                } label: {
                    HStack {
                        if model.isSaving { ProgressView().tint(StrandPalette.accent) }
                        Text(model.authMode.buttonTitle)
                            .font(StrandFont.headline)
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(StrandPalette.accent)
                .disabled(model.isSaving || !model.canSubmit)
            }
        }
    }

    private var profileCard: some View {
        StrandCard(padding: 20, tint: StrandPalette.accent) {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 14) {
                    avatar
                    VStack(alignment: .leading, spacing: 4) {
                        Text(model.displayName.isEmpty ? model.username : model.displayName)
                            .font(StrandFont.title2)
                            .foregroundStyle(StrandPalette.textPrimary)
                        Text(model.username.isEmpty ? model.user?.id ?? "Cloud profile" : "@\(model.username)")
                            .font(StrandFont.caption)
                            .foregroundStyle(StrandPalette.textTertiary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    Spacer()
                }

                profileFields

                Button {
                    Task { await model.save() }
                } label: {
                    HStack {
                        if model.isSaving { ProgressView().tint(StrandPalette.accent) }
                        Text("Save Profile")
                            .font(StrandFont.headline)
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(StrandPalette.accent)
                .disabled(model.isSaving || !model.canSubmit)
            }
        }
    }

    private var privacyCard: some View {
        StrandCard(padding: 20) {
            VStack(alignment: .leading, spacing: 14) {
                Text("FRIEND PRIVACY").strandOverline()
                privacyToggle("Share recovery", isOn: $model.shareRecovery)
                privacyToggle("Share sleep", isOn: $model.shareSleep)
                privacyToggle("Share workouts", isOn: $model.shareWorkouts)
                privacyToggle("Share daily effort", isOn: $model.shareDailyEffort)
            }
        }
    }

    private var logoutCard: some View {
        StrandCard(padding: 20) {
            VStack(alignment: .leading, spacing: 10) {
                Text("SESSION").strandOverline()
                Text("Logging out clears only this app's Cloud profile session and disables Cloud Sync.")
                    .font(StrandFont.caption)
                    .foregroundStyle(StrandPalette.textSecondary)
                Button(role: .destructive) {
                    Task { await model.logout() }
                } label: {
                    Text("Logout")
                        .font(StrandFont.headline)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(StrandPalette.metricRose)
            }
        }
    }

    private var authFields: some View {
        VStack(alignment: .leading, spacing: 12) {
            inputField("Username", text: $model.username, placeholder: "ada")
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()

            if model.authMode == .signup {
                inputField("Display name", text: $model.displayName, placeholder: "Ada")
            }

            secureInputField("Password", text: $model.password, placeholder: "At least 8 characters")
        }
    }

    private var profileFields: some View {
        VStack(alignment: .leading, spacing: 12) {
            inputField("Username", text: $model.username, placeholder: "ada")
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            inputField("Display name", text: $model.displayName, placeholder: "Ada")
            inputField("Avatar URL", text: $model.avatarURL, placeholder: "https://...")
                .textInputAutocapitalization(.never)
                .keyboardType(.URL)
                .autocorrectionDisabled()
        }
    }

    private var avatar: some View {
        ZStack {
            Circle().fill(StrandPalette.surfaceInset)
            if let first = model.avatarLetter {
                Text(first)
                    .font(StrandFont.title2)
                    .foregroundStyle(StrandPalette.accent)
            } else {
                Image(systemName: "person.crop.circle.fill")
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(StrandPalette.accent)
            }
        }
        .frame(width: 58, height: 58)
    }

    private func inputField(_ label: String, text: Binding<String>, placeholder: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label.uppercased()).strandOverline()
            TextField(placeholder, text: text)
                .font(StrandFont.body)
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 10).fill(StrandPalette.surfaceInset))
                .foregroundStyle(StrandPalette.textPrimary)
        }
    }

    private func secureInputField(_ label: String, text: Binding<String>, placeholder: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label.uppercased()).strandOverline()
            SecureField(placeholder, text: text)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .font(StrandFont.body)
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 10).fill(StrandPalette.surfaceInset))
                .foregroundStyle(StrandPalette.textPrimary)
        }
    }

    private func privacyToggle(_ title: String, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            Text(title)
                .font(StrandFont.body)
                .foregroundStyle(StrandPalette.textPrimary)
        }
        .toggleStyle(.switch)
        .tint(StrandPalette.accent)
    }
}

private enum CloudAuthMode: String, CaseIterable, Identifiable {
    case login
    case signup

    var id: String { rawValue }

    var label: String {
        switch self {
        case .login: "Login"
        case .signup: "Sign Up"
        }
    }

    var title: String {
        switch self {
        case .login: "Login"
        case .signup: "Create Cloud Account"
        }
    }

    var buttonTitle: String {
        switch self {
        case .login: "Login"
        case .signup: "Create Account"
        }
    }
}

@MainActor
private final class CloudProfileViewModel: ObservableObject {
    @Published var user: CloudUserDTO?
    @Published var authMode: CloudAuthMode = .login
    @Published var username = ""
    @Published var displayName = ""
    @Published var avatarURL = ""
    @Published var password = ""
    @Published var shareRecovery = true
    @Published var shareSleep = true
    @Published var shareWorkouts = true
    @Published var shareDailyEffort = true
    @Published var isLoading = false
    @Published var isSaving = false
    @Published var statusMessage: String?
    @Published var isError = false

    private let identityStore = KeychainIdentityStore()
    private let sessionStore = KeychainAuthSessionStore()
    private let client = HTTPFriendsClient()

    var canSubmit: Bool {
        let hasUsername = !normalizedUsername(username).isEmpty
        if user == nil {
            return hasUsername && password.count >= 8
        }
        return hasUsername
    }

    var avatarLetter: String? {
        let seed = displayName.isEmpty ? username : displayName
        guard let first = seed.trimmingCharacters(in: .whitespacesAndNewlines).first else { return nil }
        return String(first).uppercased()
    }

    func load() async {
        isLoading = true
        defer { isLoading = false }

        if let cached = CloudUserSession.cachedUser() {
            apply(cached)
        }

        let config = CloudSyncPreferences.connectionConfig()
        guard config.serverURL != nil else {
            if user == nil { setStatus("Enter your Cloud server URL in Cloud Sync first.") }
            return
        }

        let restored = await CloudUserSession.restoreIfPossible(identityStore: identityStore, sessionStore: sessionStore, client: client)
        if let restored {
            apply(restored)
            setStatus(nil)
        } else if user == nil {
            setStatus("Login or create a Cloud profile to enable sync and Friends.")
        }
    }

    func submitAuth() async {
        let config = CloudSyncPreferences.connectionConfig()
        guard config.serverURL != nil else {
            setError("Enter your Cloud server URL in Cloud Sync first.")
            return
        }

        let normalized = normalizedUsername(username)
        guard !normalized.isEmpty else {
            setError("Enter a username.")
            return
        }

        guard password.count >= 8 else {
            setError("Password must be at least 8 characters.")
            return
        }

        isSaving = true
        defer { isSaving = false }

        do {
            let identity = try? await identityStore.loadIdentity()
            let request = CloudAuthRequest(
                username: normalized,
                password: password,
                displayName: authMode == .signup ? trimmedOrNil(displayName) : nil,
                avatarUrl: authMode == .signup ? trimmedOrNil(avatarURL) : nil
            )

            let auth = authMode == .signup
                ? try await client.signup(request, identity: identity, config: config)
                : try await client.login(request, identity: identity, config: config)

            try await CloudUserSession.saveSession(auth.sessionToken, store: sessionStore)
            CloudUserSession.save(auth.user)
            apply(auth.user)
            password = ""
            setStatus(authMode == .signup ? "Cloud account created." : "Logged in.")
        } catch {
            setError(message(for: error))
        }
    }

    func save() async {
        let config = CloudSyncPreferences.connectionConfig()
        guard config.serverURL != nil else {
            setError("Enter your Cloud server URL in Cloud Sync first.")
            return
        }

        isSaving = true
        defer { isSaving = false }

        do {
            guard let session = try await sessionStore.loadSession() else {
                await CloudUserSession.clearSession(store: sessionStore)
                user = nil
                setError("Log in again before saving your Cloud profile.")
                return
            }

            let profile = CloudUserProfileRequest(
                username: trimmedOrNil(normalizedUsername(username)),
                displayName: trimmedOrNil(displayName),
                avatarUrl: trimmedOrNil(avatarURL)
            )
            let me = try await client.updateUser(profile, session: session, config: config)
            if let user = me.user {
                CloudUserSession.save(user)
                apply(user)
            }

            let privacy = CloudUserPrivacyRequest(
                shareRecovery: shareRecovery,
                shareSleep: shareSleep,
                shareWorkouts: shareWorkouts,
                shareDailyEffort: shareDailyEffort
            )
            let updated = try await client.updatePrivacy(privacy, session: session, config: config)
            if let user = updated.user {
                CloudUserSession.save(user)
                apply(user)
            }
            setStatus("Cloud profile saved.")
        } catch {
            setError(message(for: error))
        }
    }

    func logout() async {
        let config = CloudSyncPreferences.connectionConfig()
        if let session = try? await sessionStore.loadSession(), config.serverURL != nil {
            try? await client.logout(session: session, config: config)
        }
        await CloudUserSession.clearSession(store: sessionStore)
        user = nil
        password = ""
        setStatus("Logged out. Cloud Sync is disabled.")
    }

    private func apply(_ user: CloudUserDTO) {
        self.user = user
        username = user.username ?? ""
        displayName = user.displayName ?? ""
        avatarURL = user.avatarUrl ?? ""
        shareRecovery = user.shareRecovery ?? true
        shareSleep = user.shareSleep ?? true
        shareWorkouts = user.shareWorkouts ?? true
        shareDailyEffort = user.shareDailyEffort ?? true
    }

    private func setStatus(_ message: String?) {
        statusMessage = message
        isError = false
    }

    private func setError(_ message: String) {
        statusMessage = message
        isError = true
    }

    private func message(for error: Error) -> String {
        if let error = error as? CloudFriendsClientError { return error.localizedDescription }
        if let error = error as? APIClientError {
            switch error {
            case .missingDeviceToken: return "Generate a Cloud device token first."
            case .missingServerURL: return "Enter your Cloud server URL in Cloud Sync first."
            case .httpStatus(401): return "Username or password is incorrect."
            case .httpStatus(409): return "That username is already taken."
            default: return error.localizedDescription
            }
        }
        return error.localizedDescription
    }

    private func normalizedUsername(_ value: String) -> String {
        var trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        while trimmed.hasPrefix("@") {
            trimmed.removeFirst()
        }
        return trimmed.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private func trimmedOrNil(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
#endif
