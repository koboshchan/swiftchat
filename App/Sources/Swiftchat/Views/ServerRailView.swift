import SwiftchatModels
import SwiftUI

struct ServerRailView: View {
    let guilds: [Guild]
    let selectedGuildID: GuildID?
    let selectHome: () -> Void
    let selectGuild: (GuildID?) -> Void

    var body: some View {
        VStack(spacing: 10) {
            HomeRailButton(isSelected: selectedGuildID == nil, action: selectHome)

            Divider().padding(.horizontal, 12)

            ScrollView {
                LazyVStack(spacing: 10) {
                    ForEach(guilds) { guild in
                        GuildRailButton(guild: guild, isSelected: selectedGuildID == guild.id) { selectGuild(guild.id) }
                    }
                }
            }
            .scrollIndicators(.hidden)
            Spacer(minLength: 4)
        }
        .padding(.top, 12)
        .padding(.bottom, 12)
        .frame(width: ChatChromeMetrics.serverRailWidth)
        .background(.ultraThinMaterial)
        .zIndex(200)
    }
}

private struct GuildRailButton: View {
    let guild: Guild
    let isSelected: Bool
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        let displayName = guild.name.isEmpty ? "Unnamed Server" : guild.name

        HStack(spacing: 5) {
            ServerRailSelectionIndicator(
                isSelected: isSelected,
                isHovering: isHovering,
                hasNotification: guild.unreadCount > 0
            )
            Button(action: action) {
                GuildIconView(name: displayName, iconURL: guild.iconURL, size: 44, cornerRadius: 14)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(displayName)
            .help(displayName)
        }
        .frame(width: ChatChromeMetrics.serverRailWidth, height: 46, alignment: .leading)
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
        .animation(.snappy(duration: 0.18), value: isHovering)
    }
}

private struct HomeRailButton: View {
    let isSelected: Bool
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 5) {
            ServerRailSelectionIndicator(isSelected: isSelected, isHovering: isHovering, hasNotification: false)
            Button(action: action) {
                Image(systemName: "message.fill")
                    .font(.title2)
                    .frame(width: 44, height: 44)
                    .background(isSelected ? Color.accentColor : Color.secondary.opacity(0.16), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(.plain)
        }
        .frame(width: ChatChromeMetrics.serverRailWidth, height: 46, alignment: .leading)
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
        .help("Direct Messages")
    }
}

private struct ServerRailSelectionIndicator: View {
    let isSelected: Bool
    let isHovering: Bool
    let hasNotification: Bool

    var body: some View {
        Capsule()
            .fill(Color.primary)
            .frame(width: 4, height: indicatorHeight)
            .opacity(indicatorHeight == 0 ? 0 : 1)
            .frame(width: 7, height: 40)
            .animation(.snappy(duration: 0.2), value: indicatorHeight)
    }

    private var indicatorHeight: CGFloat {
        if isSelected { return 36 }
        if isHovering { return 20 }
        if hasNotification { return 8 }
        return 0
    }
}
