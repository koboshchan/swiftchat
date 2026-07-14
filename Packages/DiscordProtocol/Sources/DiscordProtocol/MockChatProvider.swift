import SwiftchatModels
import Foundation

public actor MockChatProvider: ChatProvider {
    private let currentUser: User
    private var snapshot: BootstrapSnapshot
    private var messagesByChannel: [ChannelID: [Message]]
    private var continuation: AsyncStream<ClientEvent>.Continuation?
    private var nextMessageID: UInt64

    public init() {
        let currentUser = User(
            id: UserID(rawValue: 1),
            username: "_exyron2_",
            displayName: "exy²",
            nameplate: Nameplate(label: "Cobalt demo nameplate", palette: "cobalt"),
            primaryGuild: PrimaryGuildIdentity(guildID: GuildID(rawValue: 100), tag: "EXY"),
            displayNameStyle: DisplayNameStyle(effectID: 2, colors: [0x67E8F9, 0xA78BFA])
        )
        let alex = User(id: UserID(rawValue: 2), username: "alex", displayName: "alex")
        let spiwal = User(id: UserID(rawValue: 3), username: "spiwal", displayName: "Spiwal~ ;3")
        let blahaj = User(id: UserID(rawValue: 4), username: "blahaj", displayName: "Blåhaj")
        let guild = Guild(id: GuildID(rawValue: 100), name: "Swiftcord", accentHex: 0x5865F2, unreadCount: 3)
        let secondGuild = Guild(id: GuildID(rawValue: 101), name: "Swiftchat Lab", accentHex: 0x57F287)
        let channels = [
            Channel(id: ChannelID(rawValue: 200), guildID: guild.id, name: "announcements", kind: .announcement, category: "INFO"),
            Channel(id: ChannelID(rawValue: 201), guildID: guild.id, name: "feature-announcements", category: "INFO"),
            Channel(id: ChannelID(rawValue: 202), guildID: guild.id, name: "rules-and-roles", category: "INFO"),
            Channel(id: ChannelID(rawValue: 210), guildID: guild.id, name: "general", topic: "Native macOS Discord client discussion", category: "CHAT", unreadCount: 3),
            Channel(id: ChannelID(rawValue: 211), guildID: guild.id, name: "coding-help", category: "CHAT"),
            Channel(id: ChannelID(rawValue: 212), guildID: guild.id, name: "server-suggestions", category: "CHAT"),
            Channel(id: ChannelID(rawValue: 220), guildID: guild.id, name: "suggestions", kind: .forum, category: "DEV"),
            Channel(id: ChannelID(rawValue: 221), guildID: guild.id, name: "bug-reporting", kind: .forum, category: "DEV"),
            Channel(id: ChannelID(rawValue: 230), guildID: guild.id, name: "Lounge", kind: .voice, category: "VOICE"),
            Channel(id: ChannelID(rawValue: 300), guildID: secondGuild.id, name: "native-client", topic: "Building Swiftchat in SwiftUI", category: "PROJECT"),
            Channel(id: ChannelID(rawValue: 400), guildID: nil, name: "alex", kind: .directMessage, recipients: [alex]),
        ]
        let developerRole = GuildRole(id: RoleID(rawValue: 10), name: "Developer", position: 10, colorHex: 0x57F287)
        let maintainerRole = GuildRole(id: RoleID(rawValue: 20), name: "Maintainer", position: 20, colorHex: 0xF0B232)
        let members = [
            Member(
                user: currentUser,
                roleName: "Developer",
                status: .online,
                rolePosition: 10,
                isRoleCategory: true,
                roles: [developerRole],
                activityText: "Building Swiftchat",
                customStatus: "Native, all the way down."
            ),
            Member(user: alex, roleName: "Developer", status: .idle, rolePosition: 10, isRoleCategory: true, roles: [developerRole]),
            Member(user: spiwal, roleName: "Member", isOnline: true),
            Member(user: blahaj, roleName: "Maintainer", status: .offline, rolePosition: 20, isRoleCategory: true, roles: [maintainerRole]),
        ]
        self.currentUser = currentUser
        nextMessageID = UInt64(ClientNonce.make()) ?? 9_000
        snapshot = BootstrapSnapshot(currentUser: currentUser, guilds: [guild, secondGuild], channels: channels, members: members)
        let base = Date.now.addingTimeInterval(-1_800)
        messagesByChannel = [
            ChannelID(rawValue: 210): [
                Message(id: MessageID(rawValue: 1_001), channelID: ChannelID(rawValue: 210), author: alex, content: "at first they were stored in keychain but then it required access password after every single build", timestamp: base),
                Message(id: MessageID(rawValue: 1_002), channelID: ChannelID(rawValue: 210), author: alex, content: "ill think about adding a toggle for keychain\nwill i have enough tokens to do everything i wanna accomplish thats the bigger question", timestamp: base.addingTimeInterval(30)),
                Message(id: MessageID(rawValue: 1_003), channelID: ChannelID(rawValue: 210), author: spiwal, content: "If you do please dm me the source bro or hell even put it on github it looks **REALLY GOOD**\nespecially the client parity", timestamp: base.addingTimeInterval(240), reactions: [Reaction(emoji: "🔥", count: 3)]),
                Message(id: MessageID(rawValue: 1_004), channelID: ChannelID(rawValue: 210), author: blahaj, content: "we use WebRTC for calls so the native client can rely on mature jitter buffering and media pipelines", timestamp: base.addingTimeInterval(480)),
                Message(id: MessageID(rawValue: 1_005), channelID: ChannelID(rawValue: 210), author: spiwal, content: "ohh wait that makes sense", timestamp: base.addingTimeInterval(540)),
            ],
            ChannelID(rawValue: 300): [
                Message(id: MessageID(rawValue: 2_001), channelID: ChannelID(rawValue: 300), author: currentUser, content: "Welcome to **Swiftchat Lab**. This channel is backed by the provider boundary and a durable SQLite cache.", timestamp: base),
            ],
            ChannelID(rawValue: 400): [
                Message(id: MessageID(rawValue: 3_001), channelID: ChannelID(rawValue: 400), author: alex, content: "The native shell is looking sharp 👀", timestamp: base),
            ],
        ]
    }

    public func bootstrap() async throws -> BootstrapSnapshot {
        continuation?.yield(.connectionChanged(.connecting))
        try await Task.sleep(for: .milliseconds(180))
        continuation?.yield(.connectionChanged(.ready))
        return snapshot
    }

    public func channels(in guildID: GuildID?) async throws -> [Channel] {
        snapshot.channels.filter { $0.guildID == guildID }
    }

    public func members(in guildID: GuildID?) async throws -> [Member] { snapshot.members }

    public func emojis(in guildID: GuildID) async throws -> [DiscordEmoji] {
        guard snapshot.guilds.contains(where: { $0.id == guildID }) else { return [] }
        if guildID == GuildID(rawValue: 100) {
            return [
                DiscordEmoji(id: "1512441939348295841", name: "swift_parrot", isAnimated: true, guildID: guildID),
                DiscordEmoji(id: "1512441939348295842", name: "blob_wave", guildID: guildID),
                DiscordEmoji(id: "1512441939348295843", name: "mac_happy", guildID: guildID),
            ]
        }
        return [
            DiscordEmoji(id: "1512441939348295851", name: "swiftchat", guildID: guildID),
            DiscordEmoji(id: "1512441939348295852", name: "ship_it", isAnimated: true, guildID: guildID),
        ]
    }

    public func profile(for userID: UserID, in guildID: GuildID?) async throws -> UserProfile {
        guard let member = snapshot.members.first(where: { $0.id == userID }) else {
            throw ChatProviderError.invalidRequest("That demo profile is unavailable.")
        }
        let guilds = snapshot.guilds.prefix(member.user.id == currentUser.id ? 2 : 1).map {
            MutualGuild(id: $0.id, name: $0.name, iconURL: $0.iconURL)
        }
        let friends = snapshot.members.filter { $0.id != userID }.prefix(2).map(\.user)
        return UserProfile(
            user: member.user,
            displayName: member.user.displayName,
            accentHex: member.user.id == currentUser.id ? 0x7C3AED : 0x5865F2,
            themeHexes: member.user.id == currentUser.id ? [0x1E1B4B, 0x7C3AED] : [0x172554, 0x5865F2],
            bio: member.user.id == currentUser.id
                ? "Building a native Discord client for macOS. Swift, AppKit, and too much coffee."
                : "Native apps, thoughtful interfaces, and friendly servers.",
            pronouns: member.user.id == currentUser.id ? "they/them" : nil,
            badges: [
                ProfileBadge(id: "active_developer", description: "Active Developer"),
                ProfileBadge(id: "nitro", description: "Discord Nitro"),
            ],
            mutualGuilds: Array(guilds),
            mutualFriends: Array(friends),
            mutualFriendsCount: friends.count,
            roles: member.roles.isEmpty ? [
                GuildRole(id: RoleID(rawValue: 1), name: member.roleName, position: member.rolePosition ?? 0, colorHex: 0x57F287),
            ] : member.roles,
            connectedAccounts: [
                ConnectedAccount(accountID: member.user.username, type: "github", name: member.user.username, isVerified: true),
            ],
            premiumSince: Calendar.current.date(byAdding: .year, value: -2, to: .now),
            status: member.status
        )
    }

    public func currentStatus() async -> PresenceStatus { .online }

    public func updateStatus(_ status: PresenceStatus) async throws {
        snapshot.members = snapshot.members.map { member in
            guard member.user.id == snapshot.currentUser.id else { return member }
            var updatedMember = member
            updatedMember.status = status
            return updatedMember
        }
        continuation?.yield(.snapshotChanged(snapshot))
    }

    public func messages(in channelID: ChannelID, before: MessageID?, limit: Int) async throws -> MessagePage {
        guard snapshot.channels.contains(where: { $0.id == channelID }) else { throw ChatProviderError.channelNotFound }
        var messages = messagesByChannel[channelID] ?? []
        if let before { messages = messages.filter { $0.id < before } }
        let page = Array(messages.suffix(max(1, limit)))
        return MessagePage(messages: page, hasMoreBefore: messages.count > page.count)
    }

    public func send(_ draft: SendMessageDraft) async throws -> Message {
        guard !draft.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !draft.attachmentURLs.isEmpty else {
            throw ChatProviderError.invalidRequest("A message needs text or an attachment.")
        }
        nextMessageID += 1
        let attachments = draft.attachmentURLs.enumerated().map { index, url in
            Attachment(id: "\(nextMessageID)-\(index)", filename: url.lastPathComponent, url: url, mediaType: nil)
        }
        let replyPreview = draft.replyTo.flatMap { messageID in
            messagesByChannel[draft.channelID]?.first(where: { $0.id == messageID }).map {
                MessageReplyPreview(messageID: $0.id, author: $0.author, content: $0.content)
            }
        }
        let message = Message(
            id: MessageID(rawValue: nextMessageID), channelID: draft.channelID, author: currentUser,
            content: draft.content, replyTo: draft.replyTo, replyPreview: replyPreview, attachments: attachments, nonce: draft.nonce
        )
        messagesByChannel[draft.channelID, default: []].append(message)
        continuation?.yield(.messageCreated(message))
        return message
    }

    public func edit(messageID: MessageID, channelID: ChannelID, content: String) async throws -> Message {
        guard let index = messagesByChannel[channelID]?.firstIndex(where: { $0.id == messageID }) else { throw ChatProviderError.messageNotFound }
        messagesByChannel[channelID]![index].content = content
        messagesByChannel[channelID]![index].editedTimestamp = .now
        let message = messagesByChannel[channelID]![index]
        continuation?.yield(.messageUpdated(message))
        return message
    }

    public func delete(messageID: MessageID, channelID: ChannelID) async throws {
        guard let index = messagesByChannel[channelID]?.firstIndex(where: { $0.id == messageID }) else { throw ChatProviderError.messageNotFound }
        messagesByChannel[channelID]!.remove(at: index)
        continuation?.yield(.messageDeleted(channelID: channelID, messageID: messageID))
    }

    public func toggleReaction(_ emoji: String, messageID: MessageID, channelID: ChannelID) async throws {
        guard let index = messagesByChannel[channelID]?.firstIndex(where: { $0.id == messageID }) else { throw ChatProviderError.messageNotFound }
        var message = messagesByChannel[channelID]![index]
        if let reactionIndex = message.reactions.firstIndex(where: { $0.emoji == emoji }) {
            let active = message.reactions[reactionIndex].didCurrentUserReact
            message.reactions[reactionIndex].didCurrentUserReact.toggle()
            message.reactions[reactionIndex].count += active ? -1 : 1
            if message.reactions[reactionIndex].count == 0 { message.reactions.remove(at: reactionIndex) }
        } else {
            message.reactions.append(Reaction(emoji: emoji, count: 1, didCurrentUserReact: true))
        }
        messagesByChannel[channelID]![index] = message
        continuation?.yield(.messageUpdated(message))
    }

    public func joinVoice(
        channelID: ChannelID,
        guildID: GuildID?,
        selfMute: Bool,
        selfDeaf: Bool
    ) async throws -> VoiceConnectionInfo {
        guard snapshot.channels.contains(where: { $0.id == channelID && $0.kind == .voice }) else {
            throw ChatProviderError.invalidRequest("That demo voice channel is unavailable.")
        }
        let state = VoiceParticipantState(
            userID: currentUser.id,
            channelID: channelID,
            guildID: guildID,
            sessionID: "demo-session",
            isSelfMuted: selfMute,
            isSelfDeafened: selfDeaf
        )
        continuation?.yield(.voiceStateChanged(state))
        return VoiceConnectionInfo(
            serverID: guildID?.description ?? channelID.description,
            channelID: channelID,
            guildID: guildID,
            userID: currentUser.id,
            sessionID: state.sessionID,
            token: "demo-token",
            endpoint: "mock.swiftchat.invalid"
        )
    }

    public func updateVoiceState(
        channelID: ChannelID?,
        guildID: GuildID?,
        selfMute: Bool,
        selfDeaf: Bool,
        selfVideo: Bool
    ) async throws {
        continuation?.yield(.voiceStateChanged(VoiceParticipantState(
            userID: currentUser.id,
            channelID: channelID,
            guildID: guildID,
            sessionID: "demo-session",
            isSelfMuted: selfMute,
            isSelfDeafened: selfDeaf,
            isVideoEnabled: selfVideo
        )))
    }

    public func eventStream() async -> AsyncStream<ClientEvent> {
        let stream = AsyncStream<ClientEvent>.makeStream(bufferingPolicy: .bufferingNewest(500))
        continuation = stream.continuation
        return stream.stream
    }

    public func disconnect() async {
        continuation?.yield(.connectionChanged(.disconnected))
        continuation?.finish()
        continuation = nil
    }
}
