#if os(iOS)
import SwiftUI
import StrandDesign
import NoopCloudSync

struct FriendsView: View {
    @StateObject private var model = FriendsViewModel()
    @State private var secondarySection: FriendsSecondarySection = .friends

    var body: some View {
        ScreenScaffold(title: "Friends", subtitle: "Recent synced recovery, sleep, effort, and workouts.",
                       onRefresh: { await model.load() }) {
            statusBanner

            if !model.hasCloudUser {
                loggedOutCard
            } else {
                feedSection
                secondaryPicker
                secondaryContent
            }
        }
        .task { await model.load() }
        .onReceive(NotificationCenter.default.publisher(for: CloudUserSession.didChangeNotification)) { _ in
            Task { await model.load() }
        }
    }

    @ViewBuilder
    private var statusBanner: some View {
        if model.isLoading {
            StrandCard(padding: 16) {
                HStack(spacing: 12) {
                    ProgressView().tint(StrandPalette.accent)
                    Text("Loading Friends")
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

    private var loggedOutCard: some View {
        StrandCard(padding: 22, tint: StrandPalette.accent) {
            VStack(alignment: .leading, spacing: 14) {
                Image(systemName: "person.2.slash")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(StrandPalette.accent)
                Text("Create your Cloud profile first")
                    .font(StrandFont.title2)
                    .foregroundStyle(StrandPalette.textPrimary)
                Text("Friends uses your synced snapshot data. Create or log in to a Cloud profile from Today before adding friends.")
                    .font(StrandFont.body)
                    .foregroundStyle(StrandPalette.textSecondary)
                NavigationLink {
                    CloudProfileView()
                } label: {
                    Text("Open Profile")
                        .font(StrandFont.headline)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(StrandPalette.accent)
            }
        }
    }

    private var feedSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader("Activity Feed")
            if model.feedFriends.isEmpty {
                emptyCard(
                    "No friend activity yet",
                    "Accepted friends appear here after they sync a Cloud snapshot."
                )
            } else {
                ForEach(model.feedFriends) { entry in
                    feedCard(entry)
                }
            }
        }
    }

    private var secondaryPicker: some View {
        Picker("Friends controls", selection: $secondarySection) {
            ForEach(FriendsSecondarySection.allCases) { item in
                Text(item.title).tag(item)
            }
        }
        .pickerStyle(.segmented)
    }

    @ViewBuilder
    private var secondaryContent: some View {
        switch secondarySection {
        case .friends:
            friendsContent
        case .requests:
            requestsContent
        }
    }

    private var friendsContent: some View {
        VStack(spacing: 14) {
            addFriendCard

            if model.friends.isEmpty {
                emptyCard("No accepted friends", "Add a friend by username, then wait for them to accept.")
            } else {
                ForEach(model.friends) { friend in
                    friendRow(friend, actionTitle: "Remove", systemImage: "person.fill.xmark") {
                        Task { await model.removeFriend(friend) }
                    }
                }
            }
        }
    }

    private var addFriendCard: some View {
        StrandCard(padding: 18) {
            VStack(alignment: .leading, spacing: 12) {
                Text("ADD FRIEND").strandOverline()
                HStack(spacing: 10) {
                    TextField("username", text: $model.friendUsername)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .font(StrandFont.body)
                        .padding(12)
                        .background(RoundedRectangle(cornerRadius: 10).fill(StrandPalette.surfaceInset))
                        .foregroundStyle(StrandPalette.textPrimary)

                    Button {
                        Task { await model.addFriend() }
                    } label: {
                        Image(systemName: "person.badge.plus")
                            .frame(width: 34, height: 34)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(StrandPalette.accent)
                    .disabled(model.friendUsername.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || model.isMutatingFriendship)
                }
            }
        }
    }

    private var requestsContent: some View {
        VStack(spacing: 14) {
            if model.incomingRequests.isEmpty && model.outgoingRequests.isEmpty {
                emptyCard("No pending requests", "Incoming and outgoing friend requests will appear here.")
            }

            if !model.incomingRequests.isEmpty {
                SectionHeader("Incoming")
                ForEach(model.incomingRequests) { request in
                    requestRow(request, subtitle: "Wants to connect") {
                        Button("Accept") {
                            Task { await model.accept(request) }
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(StrandPalette.accent)

                        Button("Reject") {
                            Task { await model.reject(request) }
                        }
                        .buttonStyle(.bordered)
                        .tint(StrandPalette.metricRose)
                    }
                }
            }

            if !model.outgoingRequests.isEmpty {
                SectionHeader("Outgoing")
                ForEach(model.outgoingRequests) { request in
                    requestRow(request, subtitle: "Pending") {
                        Button("Cancel") {
                            Task { await model.removeFriend(request) }
                        }
                        .buttonStyle(.bordered)
                        .tint(StrandPalette.metricRose)
                    }
                }
            }
        }
    }

    private func feedCard(_ entry: FriendFeedEntryDTO) -> some View {
        StrandCard(padding: 18, tint: StrandPalette.accent) {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 12) {
                    avatar(entry.user, size: 46)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(displayName(entry.user))
                            .font(StrandFont.title2)
                            .foregroundStyle(StrandPalette.textPrimary)
                        Text(entry.latestDailyMetric?.day ?? "No daily snapshot")
                            .font(StrandFont.caption)
                            .foregroundStyle(StrandPalette.textTertiary)
                    }
                    Spacer()
                }

                metricStrip(entry)

                if let workout = entry.recentWorkouts.first {
                    activityCapsule(
                        icon: "figure.run",
                        title: workout.sport ?? "Workout",
                        value: workout.effort.map { String(format: "%.1f effort", $0) } ?? "Workout synced",
                        detail: timestampText(workout.startTs)
                    )
                }
            }
        }
    }

    private func metricStrip(_ entry: FriendFeedEntryDTO) -> some View {
        let daily = entry.latestDailyMetric
        return HStack(spacing: 10) {
            visualStat("Recovery", daily?.recovery.map { "\(Int($0.rounded()))" } ?? "--", "%", daily?.recovery.map { $0 / 100 }, StrandPalette.chargeColor)
            visualStat("Effort", daily?.effort.map { String(format: "%.0f", $0) } ?? "--", nil, daily?.effort.map { $0 / 100 }, StrandPalette.effortColor)
            visualStat("Rest", sleepText(daily?.totalSleepMin), nil, daily?.totalSleepMin.map { $0 / 480 }, StrandPalette.restColor)
        }
    }

    private func visualStat(_ label: String, _ value: String, _ unit: String?, _ progress: Double?, _ color: Color) -> some View {
        VStack(spacing: 8) {
            MetricRingGauge(
                valueText: value,
                unitText: unit,
                progress: progress,
                tint: color,
                diameter: 66,
                lineWidth: 6,
                centerScale: 0.82
            )
            Text(label.uppercased())
                .font(StrandFont.overlineScaled(9))
                .tracking(1.1)
                .foregroundStyle(StrandPalette.textTertiary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(StrandPalette.surfaceInset))
    }

    private func activityCapsule(icon: String, title: String, value: String, detail: String?) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(StrandPalette.accent)
                .frame(width: 30, height: 30)
                .background(Circle().fill(StrandPalette.accent.opacity(0.16)))
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(StrandFont.caption)
                    .foregroundStyle(StrandPalette.textSecondary)
                Text(value)
                    .font(StrandFont.headline)
                    .foregroundStyle(StrandPalette.textPrimary)
            }
            Spacer()
            if let detail, !detail.isEmpty {
                Text(detail)
                    .font(StrandFont.caption)
                    .foregroundStyle(StrandPalette.textTertiary)
                    .lineLimit(1)
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(StrandPalette.surfaceInset))
    }

    private func friendRow(_ entry: FriendEntryDTO, actionTitle: String, systemImage: String, action: @escaping () -> Void) -> some View {
        StrandCard(padding: 18) {
            HStack(spacing: 12) {
                avatar(entry.user, size: 42)
                VStack(alignment: .leading, spacing: 3) {
                    Text(displayName(entry.user))
                        .font(StrandFont.headline)
                        .foregroundStyle(StrandPalette.textPrimary)
                    Text("@\(entry.user.username ?? "unknown")")
                        .font(StrandFont.caption)
                        .foregroundStyle(StrandPalette.textTertiary)
                }
                Spacer()
                Button(action: action) {
                    Image(systemName: systemImage)
                        .frame(width: 30, height: 30)
                }
                .buttonStyle(.bordered)
                .tint(StrandPalette.metricRose)
                .accessibilityLabel(actionTitle)
            }
        }
    }

    private func requestRow<Actions: View>(_ entry: FriendEntryDTO, subtitle: String, @ViewBuilder actions: @escaping () -> Actions) -> some View {
        StrandCard(padding: 18) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    avatar(entry.user, size: 42)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(displayName(entry.user))
                            .font(StrandFont.headline)
                            .foregroundStyle(StrandPalette.textPrimary)
                        Text("@\(entry.user.username ?? "unknown") - \(subtitle)")
                            .font(StrandFont.caption)
                            .foregroundStyle(StrandPalette.textTertiary)
                    }
                    Spacer()
                }
                HStack(spacing: 10) { actions() }
            }
        }
    }

    private func avatar(_ user: CloudUserDTO, size: CGFloat) -> some View {
        ZStack {
            Circle().fill(StrandPalette.surfaceInset)
            Text(displayName(user).prefix(1).uppercased())
                .font(StrandFont.headline)
                .foregroundStyle(StrandPalette.accent)
        }
        .frame(width: size, height: size)
    }

    private func emptyCard(_ title: String, _ message: String) -> some View {
        StrandCard(padding: 20) {
            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .font(StrandFont.headline)
                    .foregroundStyle(StrandPalette.textPrimary)
                Text(message)
                    .font(StrandFont.caption)
                    .foregroundStyle(StrandPalette.textTertiary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func displayName(_ user: CloudUserDTO) -> String {
        if let displayName = user.displayName, !displayName.isEmpty { return displayName }
        if let username = user.username, !username.isEmpty { return username }
        return "Cloud Friend"
    }

    private func sleepText(_ minutes: Double?) -> String {
        guard let minutes else { return "--" }
        let total = Int(minutes.rounded())
        return "\(total / 60)h \(total % 60)m"
    }

    private func timestampText(_ timestamp: Int?) -> String? {
        guard let timestamp, timestamp > 0 else { return nil }
        return Date(timeIntervalSince1970: TimeInterval(timestamp)).formatted(date: .omitted, time: .shortened)
    }
}

private enum FriendsSecondarySection: String, CaseIterable, Identifiable {
    case friends
    case requests

    var id: String { rawValue }

    var title: String {
        switch self {
        case .friends: "Friends"
        case .requests: "Requests"
        }
    }
}

@MainActor
private final class FriendsViewModel: ObservableObject {
    @Published var isLoading = false
    @Published var isMutatingFriendship = false
    @Published var statusMessage: String?
    @Published var isError = false
    @Published var user: CloudUserDTO?
    @Published var friendUsername = ""
    @Published var friends: [FriendEntryDTO] = []
    @Published var incomingRequests: [FriendEntryDTO] = []
    @Published var outgoingRequests: [FriendEntryDTO] = []
    @Published var feedFriends: [FriendFeedEntryDTO] = []

    private let sessionStore = KeychainAuthSessionStore()
    private let client = HTTPFriendsClient()

    var hasCloudUser: Bool { user != nil || CloudUserSession.isLoggedIn() }

    func load() async {
        let config = CloudSyncPreferences.connectionConfig()
        guard config.serverURL != nil else {
            clearRemoteState()
            setError("Enter your Cloud server URL in Cloud Sync first.")
            return
        }

        isLoading = true
        defer { isLoading = false }

        do {
            if let restored = await CloudUserSession.restoreIfPossible(sessionStore: sessionStore, client: client) {
                user = restored
            } else if let cached = CloudUserSession.cachedUser() {
                user = cached
            }

            guard let session = try await sessionStore.loadSession() else {
                if user == nil {
                    clearRemoteState()
                    setStatus("Log in or create a Cloud profile before using Friends.")
                } else {
                    setError("Your Cloud profile is loaded, but the login session token is missing. Log out and log in again.")
                }
                return
            }

            let me = try await client.userMe(session: session, config: config)
            guard let cloudUser = me.user else {
                await CloudUserSession.clearSession(store: sessionStore)
                clearRemoteState()
                setStatus("Log in or create a Cloud profile before using Friends.")
                return
            }
            CloudUserSession.save(cloudUser)
            user = cloudUser

            async let friendsListTask = client.friends(session: session, config: config)
            async let requestsListTask = client.friendRequests(session: session, config: config)
            async let feedTask = client.feed(session: session, config: config)

            let friendsList = try await friendsListTask
            friends = friendsList.friends
            let requests = try await requestsListTask
            incomingRequests = requests.incoming
            outgoingRequests = requests.outgoing
            let feed = try await feedTask
            feedFriends = feed.friends
            setStatus(nil)
        } catch {
            setError(message(for: error))
        }
    }

    func addFriend() async {
        let target = normalizedFriendUsername(friendUsername)
        guard !target.isEmpty else {
            setError("Enter a username to add a friend.")
            return
        }

        await mutateFriendship { [self] session, config in
            _ = try await client.requestFriend(FriendRequestCreateDTO(username: target), session: session, config: config)
            friendUsername = ""
            setStatus("Friend request sent.")
        }
    }

    func accept(_ request: FriendEntryDTO) async {
        await mutateFriendship { [self] session, config in
            _ = try await client.acceptFriendship(FriendshipActionRequest(friendshipId: request.friendship.id), session: session, config: config)
            setStatus("Friend request accepted.")
        }
    }

    func reject(_ request: FriendEntryDTO) async {
        await mutateFriendship { [self] session, config in
            _ = try await client.rejectFriendship(FriendshipActionRequest(friendshipId: request.friendship.id), session: session, config: config)
            setStatus("Friend request rejected.")
        }
    }

    func removeFriend(_ entry: FriendEntryDTO) async {
        await mutateFriendship { [self] session, config in
            _ = try await client.removeFriendship(FriendshipActionRequest(friendshipId: entry.friendship.id), session: session, config: config)
            setStatus("Friend removed.")
        }
    }

    private func normalizedFriendUsername(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let withoutAt = trimmed.hasPrefix("@") ? String(trimmed.dropFirst()) : trimmed
        return withoutAt.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private func mutateFriendship(_ operation: @escaping (CloudAuthSession, CloudConfig) async throws -> Void) async {
        guard user != nil else {
            setError("Log in or create a Cloud profile before using Friends.")
            return
        }

        isMutatingFriendship = true
        defer { isMutatingFriendship = false }

        do {
            let config = CloudSyncPreferences.connectionConfig()
            guard let session = try await sessionStore.loadSession() else {
                await CloudUserSession.clearSession(store: sessionStore)
                clearRemoteState()
                setError("Log in or create a Cloud profile before using Friends.")
                return
            }
            try await operation(session, config)
            await load()
        } catch {
            setError(message(for: error))
        }
    }

    private func clearRemoteState() {
        user = nil
        friends = []
        incomingRequests = []
        outgoingRequests = []
        feedFriends = []
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
            case .missingDeviceToken: return "Log in or create a Cloud profile before using Friends."
            case .missingServerURL: return "Enter your Cloud server URL in Cloud Sync first."
            case .httpStatus(409): return "Cloud profile or friend request conflict."
            case .httpStatus(404): return "User not found."
            default: return error.localizedDescription
            }
        }
        return error.localizedDescription
    }
}
#endif
