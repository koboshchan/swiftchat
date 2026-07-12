import SwiftchatModels
import SwiftUI

struct RootView: View {
    let model: AppModel
    @AppStorage("acceptedUnofficialClientRisk") private var acceptedRisk = false
    @State private var showLogin = false

    var body: some View {
        @Bindable var model = model
        HStack(spacing: 0) {
            ServerRailView(
                guilds: model.snapshot?.guilds ?? [], selectedGuildID: model.selectedGuildID,
                selectHome: { model.selectGuild(nil) }, selectGuild: model.selectGuild
            )
            Divider()
            NavigationSplitView {
                ChannelSidebarView(
                    voiceModel: model,
                    channels: model.visibleChannels,
                    selection: $model.selectedChannelID,
                    currentUser: model.snapshot?.currentUser,
                    connectionState: model.connectionState,
                    currentStatus: model.currentStatus,
                    isAuthenticated: model.isAuthenticated,
                    activeVoiceChannelID: model.activeVoiceChannel?.id,
                    connectAccount: { showLogin = true },
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
            TrafficLightGlassCapsule()
                .frame(width: 80, height: 28)
                .offset(x: 9, y: 12)
                .ignoresSafeArea()
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
        .sheet(isPresented: $showLogin) {
            DiscordLoginSheet { handle in
                await model.connectAuthenticatedAccount(handle)
                    ? nil
                    : (model.errorMessage ?? "Discord account bootstrap failed for an unknown reason.")
            }
        }
        .sheet(isPresented: $model.showQuickSwitcher) { QuickSwitcherView(model: model) }
        .sheet(isPresented: Binding(get: { !acceptedRisk }, set: { if !$0 { acceptedRisk = true } })) {
            OnboardingView(acceptedRisk: $acceptedRisk, showLogin: $showLogin)
        }
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
}
