import SwiftchatModels
import SwiftUI

struct ChannelSidebarView: View {
    let voiceModel: AppModel
    let channels: [Channel]
    @Binding var selection: ChannelID?
    let currentUser: User?
    let connectionState: ConnectionState
    let currentStatus: PresenceStatus
    let isAuthenticated: Bool
    let activeVoiceChannelID: ChannelID?
    let connectAccount: () -> Void
    let logout: () async -> Void
    let updateStatus: (PresenceStatus) async -> Void

    var body: some View {
        VStack(spacing: 0) {
            ServerChannelHeader(guild: selectedGuild)
            Divider()

            List(selection: $selection) {
                ForEach(ChannelGroup.make(from: channels)) { group in
                    ChannelGroupRows(
                        group: group,
                        activeVoiceChannelID: activeVoiceChannelID,
                        voiceParticipantsByChannel: voiceSidebarParticipantsByChannel
                    )
                }
            }
            .listStyle(.sidebar)

            AccountControlView(
                voiceModel: voiceModel,
                user: currentUser,
                connectionState: connectionState,
                currentStatus: currentStatus,
                isAuthenticated: isAuthenticated,
                connectAccount: connectAccount,
                logout: logout,
                updateStatus: updateStatus
            )
        }
        .navigationTitle("")
    }

    private var selectedGuild: Guild? {
        guard let guildID = voiceModel.selectedGuildID else { return nil }
        return voiceModel.snapshot?.guilds.first(where: { $0.id == guildID })
    }

    private var voiceSidebarParticipantsByChannel: [ChannelID: [VoiceSidebarParticipant]] {
        let currentUserID = currentUser?.id
        let voiceChannelIDs = Set(channels.filter { $0.kind == .voice }.map(\.id))
        var statesByChannel: [ChannelID: [UserID: VoiceParticipantState]] = [:]
        for state in voiceModel.voiceStates.values {
            guard let channelID = state.channelID, voiceChannelIDs.contains(channelID) else { continue }
            statesByChannel[channelID, default: [:]][state.userID] = state
        }

        if let channelID = activeVoiceChannelID,
           let currentUserID,
           statesByChannel[channelID]?[currentUserID] == nil {
            statesByChannel[channelID, default: [:]][currentUserID] = VoiceParticipantState(
                userID: currentUserID,
                channelID: channelID,
                guildID: voiceModel.activeVoiceChannel?.guildID,
                sessionID: "local",
                isSelfMuted: voiceModel.isVoiceMuted,
                isSelfDeafened: voiceModel.isVoiceDeafened,
                isVideoEnabled: voiceModel.isCameraEnabled
            )
        }

        return statesByChannel.mapValues { statesByUser in statesByUser.map { userID, state in
            let user = currentUser?.id == userID
                ? currentUser
                : voiceModel.members.first(where: { $0.id == userID })?.user
            return VoiceSidebarParticipant(
                id: userID,
                name: user?.displayName ?? "User \(userID.rawValue)",
                avatarURL: user?.avatarURL,
                isCurrentUser: userID == currentUserID,
                isMuted: state.isMuted || state.isSelfMuted,
                isDeafened: state.isDeafened || state.isSelfDeafened,
                isStreaming: state.isStreaming,
                isVideoEnabled: state.isVideoEnabled
            )
        }.sorted {
            if $0.isCurrentUser != $1.isCurrentUser { return $0.isCurrentUser }
            return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }}
    }
}

private struct ServerChannelHeader: View {
    let guild: Guild?

    var body: some View {
        HStack(spacing: 10) {
            if let guild {
                GuildHeaderIcon(guild: guild)
                Text(guild.name)
                    .font(.headline)
                    .lineLimit(1)
            } else {
                Image(systemName: "message.fill")
                    .font(.callout.weight(.semibold))
                    .frame(width: 30, height: 30)
                    .background(Color.accentColor.opacity(0.18), in: RoundedRectangle(cornerRadius: 9))
                Text("Messages").font(.headline)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .frame(height: 50)
        .accessibilityElement(children: .combine)
    }
}

private struct GuildHeaderIcon: View {
    let guild: Guild

    var body: some View {
        Group {
            if let iconURL = guild.iconURL {
                AsyncImage(url: iconURL) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    initials
                }
            } else {
                initials
            }
        }
        .frame(width: 30, height: 30)
        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
    }

    private var initials: some View {
        Text(guild.name.split(separator: " ").prefix(2).compactMap(\.first).map(String.init).joined())
            .font(.caption.weight(.bold))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(hex: guild.accentHex))
    }
}

private struct VoiceSidebarParticipant: Identifiable {
    let id: UserID
    let name: String
    let avatarURL: URL?
    let isCurrentUser: Bool
    let isMuted: Bool
    let isDeafened: Bool
    let isStreaming: Bool
    let isVideoEnabled: Bool
}

struct ChannelGroup: Identifiable {
    let id: String
    let name: String?
    let position: Int
    var channels: [Channel]

    static func make(from channels: [Channel]) -> [ChannelGroup] {
        var result: [ChannelGroup] = []
        for channel in channels {
            let groupID = channel.categoryID?.description ?? "uncategorized"
            if let index = result.firstIndex(where: { $0.id == groupID }) {
                result[index].channels.append(channel)
            } else {
                result.append(ChannelGroup(
                    id: groupID,
                    name: channel.category,
                    position: channel.categoryPosition,
                    channels: [channel]
                ))
            }
        }
        for index in result.indices {
            result[index].channels.sort(by: channelOrder)
        }
        return result.sorted { lhs, rhs in
            if lhs.name == nil, rhs.name != nil { return true }
            if lhs.name != nil, rhs.name == nil { return false }
            return lhs.position < rhs.position
        }
    }

    private static func channelOrder(_ lhs: Channel, _ rhs: Channel) -> Bool {
        let lhsIsVoice = lhs.kind == .voice
        let rhsIsVoice = rhs.kind == .voice
        if lhsIsVoice != rhsIsVoice { return !lhsIsVoice }
        if lhs.position != rhs.position { return lhs.position < rhs.position }
        return lhs.id < rhs.id
    }
}

private struct ChannelGroupRows: View {
    let group: ChannelGroup
    let activeVoiceChannelID: ChannelID?
    let voiceParticipantsByChannel: [ChannelID: [VoiceSidebarParticipant]]
    @SceneStorage private var isExpanded: Bool

    init(
        group: ChannelGroup,
        activeVoiceChannelID: ChannelID?,
        voiceParticipantsByChannel: [ChannelID: [VoiceSidebarParticipant]]
    ) {
        self.group = group
        self.activeVoiceChannelID = activeVoiceChannelID
        self.voiceParticipantsByChannel = voiceParticipantsByChannel
        _isExpanded = SceneStorage(wrappedValue: true, "dev.swiftchat.channel-category.\(group.id).expanded")
    }

    var body: some View {
        Section {
            if group.name == nil || isExpanded {
                ForEach(group.channels) { channel in
                    if channel.kind == .voice {
                        ChannelRow(
                            channel: channel,
                            isVoiceConnected: activeVoiceChannelID == channel.id
                        )
                        .tag(channel.id)
                        ForEach(voiceParticipantsByChannel[channel.id] ?? []) { participant in
                            VoiceParticipantRow(participant: participant)
                        }
                    } else {
                        ChannelRow(channel: channel).tag(channel.id)
                    }
                }
            }
        } header: {
            if let name = group.name {
                Button {
                    withAnimation(.snappy(duration: 0.18)) { isExpanded.toggle() }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                            .font(.caption2.weight(.semibold))
                            .frame(width: 8)
                        Text(name)
                        Spacer(minLength: 0)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(isExpanded ? "Collapse \(name)" : "Expand \(name)")
            }
        }
    }
}

private struct VoiceParticipantRow: View {
    let participant: VoiceSidebarParticipant

    var body: some View {
        HStack(spacing: 8) {
            AvatarView(name: participant.name, url: participant.avatarURL, size: 24)
            Text(participant.name)
                .font(.caption)
                .lineLimit(1)
            Spacer(minLength: 4)
            if participant.isStreaming {
                Image(systemName: "display")
                    .foregroundStyle(Color(hex: 0x23A55A))
            }
            if participant.isVideoEnabled {
                Image(systemName: "video.fill")
                    .foregroundStyle(.secondary)
            }
            if participant.isMuted {
                Image(systemName: "mic.slash.fill")
                    .foregroundStyle(.secondary)
            }
            if participant.isDeafened {
                Image(systemName: "headphones.slash")
                    .foregroundStyle(.secondary)
            }
        }
        .font(.caption2)
        .padding(.leading, 24)
        .padding(.vertical, 1)
        .accessibilityLabel(participant.name)
        .accessibilityValue(
            participant.isMuted && participant.isDeafened ? "Muted, Deafened"
                : participant.isMuted ? "Muted"
                : participant.isDeafened ? "Deafened"
                : "Connected"
        )
    }
}

private struct AccountControlView: View {
    let voiceModel: AppModel
    let user: User?
    let connectionState: ConnectionState
    let currentStatus: PresenceStatus
    let isAuthenticated: Bool
    let connectAccount: () -> Void
    let logout: () async -> Void
    let updateStatus: (PresenceStatus) async -> Void
    @State private var confirmLogout = false

    var body: some View {
        GlassEffectContainer(spacing: 0) {
            VStack(spacing: 0) {
                if voiceModel.activeVoiceChannel != nil {
                    VoiceSidebarStatus(model: voiceModel)
                    Divider().padding(.horizontal, 10)
                }

                HStack(spacing: 9) {
                    AccountAvatar(name: displayName, avatarURL: user?.avatarURL, status: currentStatus)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(displayName).font(.callout.weight(.semibold)).lineLimit(1)
                        Text(accountSubtitle).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Spacer(minLength: 4)
                    AccountMenu(
                        isAuthenticated: isAuthenticated,
                        currentStatus: currentStatus,
                        connectAccount: connectAccount,
                        requestLogout: { confirmLogout = true },
                        updateStatus: updateStatus
                    )
                }
                .padding(.horizontal, 10)
                .frame(height: ChatChromeMetrics.controlHeight)
            }
            .glassEffect(
                .regular.interactive(),
                in: RoundedRectangle(cornerRadius: ChatChromeMetrics.controlCornerRadius, style: .continuous)
            )
        }
        .padding(.horizontal, 8)
        .padding(.top, 8)
        .padding(.bottom, 12)
        .confirmationDialog("Log out of Discord?", isPresented: $confirmLogout) {
            Button("Log Out", role: .destructive) { Task { await logout() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Swiftchat will remove this account's saved session from Keychain.")
        }
    }

    private var displayName: String {
        isAuthenticated ? (user?.displayName ?? "Discord Account") : "Connect Account"
    }

    private var accountSubtitle: String {
        if isAuthenticated { return user.map { "@\($0.username)" } ?? connectionState.rawValue }
        return "Sign in to Discord"
    }
}

private struct AccountAvatar: View {
    let name: String
    let avatarURL: URL?
    let status: PresenceStatus

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            AvatarView(name: name, url: avatarURL, size: 34)
            Circle()
                .fill(status.color)
                .frame(width: 9, height: 9)
                .overlay(Circle().stroke(.background, lineWidth: 2))
        }
    }
}

private struct AccountMenu: View {
    let isAuthenticated: Bool
    let currentStatus: PresenceStatus
    let connectAccount: () -> Void
    let requestLogout: () -> Void
    let updateStatus: (PresenceStatus) async -> Void

    var body: some View {
        Menu {
            if isAuthenticated {
                Menu("Set Status", systemImage: "circle.dotted") {
                    ForEach(PresenceStatus.allCases.filter { $0 != .offline }, id: \.self) { status in
                        Button {
                            Task { await updateStatus(status) }
                        } label: {
                            if status == currentStatus { Label(status.label, systemImage: "checkmark") }
                            else { Text(status.label) }
                        }
                    }
                }
                Button("Switch Account…", systemImage: "person.2", action: connectAccount)
                Divider()
                Button("Log Out", systemImage: "rectangle.portrait.and.arrow.right", role: .destructive, action: requestLogout)
            } else {
                Button("Connect Discord Account…", systemImage: "person.crop.circle.badge.plus", action: connectAccount)
            }
            Divider()
            SettingsLink { Label("Settings…", systemImage: "gearshape") }
        } label: {
            Image(systemName: "gearshape.fill")
                .font(.body)
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .help("Account and Settings")
    }
}

private extension PresenceStatus {
    var label: String {
        switch self {
        case .online: "Online"
        case .idle: "Idle"
        case .dnd: "Do Not Disturb"
        case .invisible: "Invisible"
        case .offline: "Offline"
        }
    }

    var color: Color {
        switch self {
        case .online: .green
        case .idle: .orange
        case .dnd: .red
        case .invisible, .offline: .gray
        }
    }
}

private struct ChannelRow: View {
    let channel: Channel
    var isVoiceConnected = false

    var body: some View {
        content
    }

    private var content: some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .foregroundStyle(isVoiceConnected ? Color.green : Color.secondary)
                .frame(width: 16)
            Text(channel.name).lineLimit(1)
            Spacer()
            if isVoiceConnected {
                Image(systemName: "waveform")
                    .font(.caption)
                    .foregroundStyle(.green)
            }
            if channel.unreadCount > 0 {
                Text(channel.unreadCount, format: .number)
                    .font(.caption2.bold()).padding(.horizontal, 6).padding(.vertical, 2).background(.red, in: Capsule())
            }
        }
    }

    private var systemImage: String {
        switch channel.kind {
        case .voice: "speaker.wave.2.fill"
        case .forum: "bubble.left.and.bubble.right.fill"
        case .directMessage, .groupDirectMessage: "person.fill"
        case .announcement: "megaphone.fill"
        default: "number"
        }
    }
}
