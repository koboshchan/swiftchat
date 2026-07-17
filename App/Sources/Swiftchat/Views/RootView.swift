import SwiftchatModels
import SwiftUI

struct RootView: View {
    let model: AppModel

    var body: some View {
        switch model.sessionState {
        case .workspace:
            ChatRootView(model: model)
        case .signedOut:
            if model.launchMode == .normal {
                DiscordLoginView(
                    showsCancel: false,
                    networkingEnabled: !model.isDiscordNetworkingDisabled
                ) { handle in
                    await model.connectAuthenticatedAccount(
                        handle,
                        preservesInteractivePresentation: true
                    )
                        ? nil
                        : (model.errorMessage ?? "Discord account bootstrap failed for an unknown reason.")
                }
            } else {
                SwiftchatSessionLoadingView(
                    state: model.sessionState,
                    isOfflineTesting: model.isOfflineTesting
                )
            }
        case .restoring, .connecting:
            SwiftchatSessionLoadingView(
                state: model.sessionState,
                isOfflineTesting: model.isOfflineTesting
            )
        }
    }
}

private struct SwiftchatSessionLoadingView: View {
    let state: AppModel.SessionState
    let isOfflineTesting: Bool

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(hex: 0x130D19), Color(hex: 0x211326), Color(hex: 0x100C17)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            RadialGradient(
                colors: [Color(hex: 0xFF5C9C).opacity(0.24), .clear],
                center: .bottomLeading,
                startRadius: 20,
                endRadius: 720
            )

            VStack(spacing: 14) {
                ProgressView()
                    .controlSize(.large)
                    .tint(Color(hex: 0xFF79AA))
                    .frame(width: 58, height: 58)
                    .background(Color.white.opacity(0.055), in: Circle())
                Text("Opening Swiftchat")
                    .font(.title2.bold())
                    .foregroundStyle(.white)
                Text(detail)
                    .font(.callout)
                    .foregroundStyle(.white.opacity(0.62))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .preferredColorScheme(.dark)
    }

    private var detail: String {
        if isOfflineTesting { return "Loading offline testing data…" }
        switch state {
        case .restoring: return "Checking your saved session…"
        case .connecting: return "Loading your Discord workspace…"
        case .signedOut, .workspace: return "Getting things ready…"
        }
    }
}

private struct ChatRootView: View {
    let model: AppModel
    @State private var showLogin = false
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    var body: some View {
        @Bindable var model = model
        HStack(spacing: 0) {
            ServerRailView(
                guilds: model.snapshot?.guilds ?? [], selectedGuildID: model.selectedGuildID,
                selectHome: { model.selectGuild(nil) }, selectGuild: model.selectGuild
            )
            .zIndex(200)
            Divider()
            NavigationSplitView(columnVisibility: $columnVisibility) {
                ChannelSidebarView(
                    voiceModel: model,
                    guild: selectedGuild,
                    channels: model.visibleChannels,
                    selection: $model.selectedChannelID,
                    currentUser: model.snapshot?.currentUser,
                    connectionState: model.connectionState,
                    currentStatus: model.currentStatus,
                    isAuthenticated: model.isAuthenticated,
                    isOfflineTesting: model.isOfflineTesting,
                    activeVoiceChannelID: model.activeVoiceChannel?.id,
                    connectAccount: {
                        if !model.isOfflineTesting { showLogin = true }
                    },
                    logout: { await model.logout() },
                    updateStatus: { await model.updateStatus($0) }
                )
                    .navigationSplitViewColumnWidth(min: 190, ideal: 230, max: 310)
            } detail: {
                ChatWorkspaceView(model: model)
                    .toolbarBackgroundVisibility(.visible, for: .windowToolbar)
                    .toolbar(id: "swiftchat-main-v2") {
                        ToolbarItem(id: "channel") {
                            if let channel = model.selectedChannel {
                                Button { model.showQuickSwitcher = true } label: {
                                    Label(channel.name, systemImage: channelToolbarSymbol(channel))
                                        .labelStyle(.titleAndIcon)
                                }
                            }
                        }
                        .visibilityPriority(.high)
                        ToolbarSpacer(.flexible)
                        ToolbarItem(id: "quick-switcher") {
                            Button { model.showQuickSwitcher = true } label: { Label("Quick Switcher", systemImage: "magnifyingglass") }
                        }
                        .visibilityPriority(.high)
                        ToolbarItem(id: "members") {
                            Button { model.showInspector.toggle() } label: { Label("Members", systemImage: "person.2") }
                        }
                        .visibilityPriority(.high)
                    }
            }
        }
        .overlay(alignment: .topLeading) {
            ZStack(alignment: .topLeading) {
                TrafficLightGlassCapsule()
                    .frame(width: 80, height: 28)
                    .offset(x: 9, y: 12)
                    .accessibilityHidden(true)

                if columnVisibility != .detailOnly {
                    SidebarServerIdentity(guild: selectedGuild)
                        .frame(width: 150, height: 28, alignment: .leading)
                        .offset(x: ChatChromeMetrics.sidebarIdentityLeadingOffset, y: 12)
                }
            }
            .ignoresSafeArea()
            .allowsHitTesting(false)
        }
        .sheet(isPresented: $showLogin) {
            DiscordLoginView(
                showsCancel: true,
                networkingEnabled: !model.isDiscordNetworkingDisabled
            ) { handle in
                await model.connectAuthenticatedAccount(
                    handle,
                    preservesInteractivePresentation: true
                )
                    ? nil
                    : (model.errorMessage ?? "Discord account bootstrap failed for an unknown reason.")
            }
        }
        .sheet(isPresented: $model.showQuickSwitcher) { QuickSwitcherView(model: model) }
        .alert("Swiftchat", isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.dismissError() } })) {
            Button("OK") { model.dismissError() }
        } message: {
            Text(model.errorMessage ?? "Unknown error")
        }
        .onReceive(NotificationCenter.default.publisher(for: .swiftchatQuickSwitcher)) { _ in model.showQuickSwitcher = true }
        .onReceive(NotificationCenter.default.publisher(for: .swiftchatToggleInspector)) { _ in model.showInspector.toggle() }
    }

    private func channelToolbarSymbol(_ channel: Channel) -> String {
        switch channel.kind {
        case .voice: "speaker.wave.2.fill"
        case .directMessage, .groupDirectMessage: "person.fill"
        case .announcement: "megaphone.fill"
        case .forum: "bubble.left.and.bubble.right.fill"
        default: "number"
        }
    }

    private var selectedGuild: Guild? {
        guard let guildID = model.selectedGuildID else { return nil }
        return model.snapshot?.guilds.first(where: { $0.id == guildID })
    }
}
