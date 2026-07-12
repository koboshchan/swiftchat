import SwiftchatModels
import SwiftUI

struct ServerRailView: View {
    let guilds: [Guild]
    let selectedGuildID: GuildID?
    let selectHome: () -> Void
    let selectGuild: (GuildID?) -> Void

    var body: some View {
        VStack(spacing: 10) {
            Button(action: selectHome) {
                Image(systemName: "message.fill")
                    .font(.title2)
                    .frame(width: 44, height: 44)
                    .background(selectedGuildID == nil ? Color.accentColor : Color.secondary.opacity(0.16), in: RoundedRectangle(cornerRadius: selectedGuildID == nil ? 14 : 22))
            }
            .buttonStyle(.plain)
            .help("Direct Messages")

            Divider().padding(.horizontal, 12)

            ScrollView {
                LazyVStack(spacing: 10) {
                    ForEach(Array(guilds.reversed())) { guild in
                        GuildRailButton(guild: guild, isSelected: selectedGuildID == guild.id) { selectGuild(guild.id) }
                    }
                }
            }
            Spacer(minLength: 4)
        }
        .padding(.top, 12)
        .padding(.bottom, 12)
        .frame(width: ChatChromeMetrics.serverRailWidth)
        .background(.ultraThinMaterial)
    }
}

private struct GuildRailButton: View {
    let guild: Guild
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack(alignment: .topTrailing) {
                if let iconURL = guild.iconURL {
                    AsyncImage(url: iconURL) { image in image.resizable().scaledToFill() } placeholder: { initials }
                        .frame(width: 44, height: 44).clipShape(RoundedRectangle(cornerRadius: isSelected ? 14 : 22))
                } else { initials }
                if guild.unreadCount > 0 {
                    Text(guild.unreadCount, format: .number)
                        .font(.caption2.bold()).padding(4).background(.red, in: Circle()).offset(x: 4, y: -4)
                }
            }
        }
        .buttonStyle(.plain)
        .help(guild.name)
    }

    private var initials: some View {
        Text(guild.name.split(separator: " ").prefix(2).compactMap(\.first).map(String.init).joined())
            .font(.headline)
            .frame(width: 44, height: 44)
            .background(Color(hex: guild.accentHex).opacity(isSelected ? 1 : 0.72), in: RoundedRectangle(cornerRadius: isSelected ? 14 : 22))
    }
}
