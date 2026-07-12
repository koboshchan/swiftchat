import SwiftchatModels
import SwiftUI

struct ChannelSidebarView: View {
    let channels: [Channel]
    @Binding var selection: ChannelID?
    let currentUser: User?
    let connectionState: ConnectionState
    let currentStatus: PresenceStatus
    let isAuthenticated: Bool
    let connectAccount: () -> Void
    let logout: () async -> Void
    let updateStatus: (PresenceStatus) async -> Void

    var body: some View {
        VStack(spacing: 0) {
            List(selection: $selection) {
                ForEach(ChannelGroup.make(from: channels)) { group in
                    ChannelGroupRows(group: group)
                }
            }
            .listStyle(.sidebar)

            AccountControlView(
                user: currentUser,
                connectionState: connectionState,
                currentStatus: currentStatus,
                isAuthenticated: isAuthenticated,
                connectAccount: connectAccount,
                logout: logout,
                updateStatus: updateStatus
            )
        }
        .navigationTitle(channels.first?.guildID == nil ? "Messages" : "Swiftcord")
    }
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
    @SceneStorage private var isExpanded: Bool

    init(group: ChannelGroup) {
        self.group = group
        _isExpanded = SceneStorage(wrappedValue: true, "dev.swiftchat.channel-category.\(group.id).expanded")
    }

    var body: some View {
        Section {
            if group.name == nil || isExpanded {
                ForEach(group.channels) { channel in
                    ChannelRow(channel: channel).tag(channel.id)
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

private struct AccountControlView: View {
    let user: User?
    let connectionState: ConnectionState
    let currentStatus: PresenceStatus
    let isAuthenticated: Bool
    let connectAccount: () -> Void
    let logout: () async -> Void
    let updateStatus: (PresenceStatus) async -> Void
    @State private var confirmLogout = false

    var body: some View {
        GlassEffectContainer(spacing: 8) {
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

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage).foregroundStyle(.secondary).frame(width: 16)
            Text(channel.name).lineLimit(1)
            Spacer()
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
