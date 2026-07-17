import Foundation
import Synchronization

public struct Nameplate: Codable, Hashable, Sendable {
    public var staticURL: URL?
    public var animatedURL: URL?
    public var label: String
    public var palette: String

    public init(staticURL: URL? = nil, animatedURL: URL? = nil, label: String = "", palette: String = "none") {
        self.staticURL = staticURL
        self.animatedURL = animatedURL
        self.label = label
        self.palette = palette
    }
}

public struct PrimaryGuildIdentity: Codable, Hashable, Sendable {
    public var guildID: GuildID?
    public var tag: String?
    public var badgeURL: URL?

    public init(guildID: GuildID? = nil, tag: String? = nil, badgeURL: URL? = nil) {
        self.guildID = guildID
        self.tag = tag
        self.badgeURL = badgeURL
    }
}

public struct DisplayNameStyle: Codable, Hashable, Sendable {
    public var fontID: Int
    public var effectID: Int
    public var colors: [UInt32]

    public init(fontID: Int = 11, effectID: Int = 1, colors: [UInt32] = []) {
        self.fontID = fontID
        self.effectID = effectID
        self.colors = colors
    }
}

public struct User: Identifiable, Codable, Hashable, Sendable {
    public let id: UserID
    public var username: String
    public var displayName: String
    public var avatarURL: URL?
    public var isBot: Bool
    public var avatarDecorationURL: URL?
    public var nameplate: Nameplate?
    public var primaryGuild: PrimaryGuildIdentity?
    public var displayNameStyle: DisplayNameStyle?
    public var publicFlags: UInt64
    public var premiumType: Int

    public init(
        id: UserID,
        username: String,
        displayName: String,
        avatarURL: URL? = nil,
        isBot: Bool = false,
        avatarDecorationURL: URL? = nil,
        nameplate: Nameplate? = nil,
        primaryGuild: PrimaryGuildIdentity? = nil,
        displayNameStyle: DisplayNameStyle? = nil,
        publicFlags: UInt64 = 0,
        premiumType: Int = 0
    ) {
        self.id = id
        self.username = username
        self.displayName = displayName
        self.avatarURL = avatarURL
        self.isBot = isBot
        self.avatarDecorationURL = avatarDecorationURL
        self.nameplate = nameplate
        self.primaryGuild = primaryGuild
        self.displayNameStyle = displayNameStyle
        self.publicFlags = publicFlags
        self.premiumType = premiumType
    }

    private enum CodingKeys: String, CodingKey {
        case id, username, displayName, avatarURL, isBot, avatarDecorationURL, nameplate
        case primaryGuild, displayNameStyle, publicFlags, premiumType
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UserID.self, forKey: .id)
        username = try container.decodeIfPresent(String.self, forKey: .username) ?? id.description
        displayName = try container.decodeIfPresent(String.self, forKey: .displayName) ?? username
        avatarURL = try container.decodeIfPresent(URL.self, forKey: .avatarURL)
        isBot = try container.decodeIfPresent(Bool.self, forKey: .isBot) ?? false
        avatarDecorationURL = try container.decodeIfPresent(URL.self, forKey: .avatarDecorationURL)
        nameplate = try container.decodeIfPresent(Nameplate.self, forKey: .nameplate)
        primaryGuild = try container.decodeIfPresent(PrimaryGuildIdentity.self, forKey: .primaryGuild)
        displayNameStyle = try container.decodeIfPresent(DisplayNameStyle.self, forKey: .displayNameStyle)
        publicFlags = try container.decodeIfPresent(UInt64.self, forKey: .publicFlags) ?? 0
        premiumType = try container.decodeIfPresent(Int.self, forKey: .premiumType) ?? 0
    }
}

public struct Guild: Identifiable, Codable, Hashable, Sendable {
    public let id: GuildID
    public var name: String
    public var iconURL: URL?
    public var accentHex: UInt32
    public var unreadCount: Int

    public init(id: GuildID, name: String, iconURL: URL? = nil, accentHex: UInt32 = 0x5865F2, unreadCount: Int = 0) {
        self.id = id
        self.name = name
        self.iconURL = iconURL
        self.accentHex = accentHex
        self.unreadCount = unreadCount
    }
}

public struct DiscordEmoji: Identifiable, Codable, Hashable, Sendable {
    public let id: String
    public var name: String
    public var isAnimated: Bool
    public var guildID: GuildID
    public var isAvailable: Bool

    public init(
        id: String,
        name: String,
        isAnimated: Bool = false,
        guildID: GuildID,
        isAvailable: Bool = true
    ) {
        self.id = id
        self.name = name
        self.isAnimated = isAnimated
        self.guildID = guildID
        self.isAvailable = isAvailable
    }

    public var messageToken: String { "<\(isAnimated ? "a" : ""):\(name):\(id)>" }
    public var reactionToken: String { "\(name):\(id)" }

    public var imageURL: URL? {
        URL(string: "https://cdn.discordapp.com/emojis/\(id).webp?size=96&animated=\(isAnimated ? "true" : "false")")
    }

    public var linkedImageMarkdown: String {
        "[\(name)](https://cdn.discordapp.com/emojis/\(id).\(isAnimated ? "gif" : "webp")?size=48&animated=\(isAnimated ? "true" : "false")&name=\(name)&lossless=true)"
    }
}

public struct EmojiUserSettings: Equatable, Sendable {
    public var favoriteKeys: Set<String>
    public var usageScores: [String: Int]

    public init(favoriteKeys: Set<String> = [], usageScores: [String: Int] = [:]) {
        self.favoriteKeys = favoriteKeys
        self.usageScores = usageScores
    }
}

public enum ChannelKindValue: String, Codable, Hashable, Sendable {
    case text, announcement, forum, voice, directMessage, groupDirectMessage, unknown
}

public struct Channel: Identifiable, Codable, Hashable, Sendable {
    public let id: ChannelID
    public var guildID: GuildID?
    public var name: String
    public var topic: String?
    public var kind: ChannelKindValue
    public var category: String?
    public var categoryID: ChannelID?
    public var position: Int
    public var categoryPosition: Int
    public var unreadCount: Int
    public var isMuted: Bool
    public var recipients: [User]

    public init(
        id: ChannelID,
        guildID: GuildID?,
        name: String,
        topic: String? = nil,
        kind: ChannelKindValue = .text,
        category: String? = nil,
        categoryID: ChannelID? = nil,
        position: Int = 0,
        categoryPosition: Int = 0,
        unreadCount: Int = 0,
        isMuted: Bool = false,
        recipients: [User] = []
    ) {
        self.id = id
        self.guildID = guildID
        self.name = name
        self.topic = topic
        self.kind = kind
        self.category = category
        self.categoryID = categoryID
        self.position = position
        self.categoryPosition = categoryPosition
        self.unreadCount = unreadCount
        self.isMuted = isMuted
        self.recipients = recipients
    }
}

public enum PresenceStatus: String, Codable, CaseIterable, Hashable, Sendable {
    case online, idle, dnd, invisible, offline

    public var isVisibleOnline: Bool { self == .online || self == .idle || self == .dnd }
}

public struct GuildRole: Identifiable, Codable, Hashable, Sendable {
    public let id: RoleID
    public var name: String
    public var position: Int
    public var colorHex: UInt32?
    public var iconURL: URL?
    public var unicodeEmoji: String?

    public init(
        id: RoleID,
        name: String,
        position: Int = 0,
        colorHex: UInt32? = nil,
        iconURL: URL? = nil,
        unicodeEmoji: String? = nil
    ) {
        self.id = id
        self.name = name
        self.position = position
        self.colorHex = colorHex
        self.iconURL = iconURL
        self.unicodeEmoji = unicodeEmoji
    }
}

public struct Attachment: Identifiable, Codable, Hashable, Sendable {
    public let id: String
    public var filename: String
    public var url: URL
    public var proxyURL: URL?
    public var mediaType: String?
    public var width: Int?
    public var height: Int?
    public var size: Int
    public var description: String?

    public init(id: String, filename: String, url: URL, proxyURL: URL? = nil, mediaType: String? = nil, width: Int? = nil, height: Int? = nil, size: Int = 0, description: String? = nil) {
        self.id = id
        self.filename = filename
        self.url = url
        self.proxyURL = proxyURL
        self.mediaType = mediaType
        self.width = width
        self.height = height
        self.size = size
        self.description = description
    }
}

public struct Reaction: Identifiable, Codable, Hashable, Sendable {
    public var id: String { emoji }
    public var emoji: String
    public var count: Int
    public var didCurrentUserReact: Bool

    public init(emoji: String, count: Int, didCurrentUserReact: Bool = false) {
        self.emoji = emoji
        self.count = count
        self.didCurrentUserReact = didCurrentUserReact
    }
}

public enum OutboxState: String, Codable, Hashable, Sendable {
    case confirmed, queued, uploading, sending, failed
}

public struct MessageReplyPreview: Codable, Hashable, Sendable {
    public var messageID: MessageID
    public var author: User
    public var content: String

    public init(messageID: MessageID, author: User, content: String) {
        self.messageID = messageID
        self.author = author
        self.content = content
    }
}

public struct Message: Identifiable, Codable, Hashable, Sendable {
    public let id: MessageID
    public var channelID: ChannelID
    public var author: User
    public var content: String
    public var timestamp: Date
    public var editedTimestamp: Date?
    public var replyTo: MessageID?
    public var replyPreview: MessageReplyPreview?
    public var attachments: [Attachment]
    public var reactions: [Reaction]
    public var nonce: String?
    public var outboxState: OutboxState

    public init(
        id: MessageID,
        channelID: ChannelID,
        author: User,
        content: String,
        timestamp: Date = .now,
        editedTimestamp: Date? = nil,
        replyTo: MessageID? = nil,
        replyPreview: MessageReplyPreview? = nil,
        attachments: [Attachment] = [],
        reactions: [Reaction] = [],
        nonce: String? = nil,
        outboxState: OutboxState = .confirmed
    ) {
        self.id = id
        self.channelID = channelID
        self.author = author
        self.content = content
        self.timestamp = timestamp
        self.editedTimestamp = editedTimestamp
        self.replyTo = replyTo
        self.replyPreview = replyPreview
        self.attachments = attachments
        self.reactions = reactions
        self.nonce = nonce
        self.outboxState = outboxState
    }
}

public struct Member: Identifiable, Codable, Hashable, Sendable {
    public var id: UserID { user.id }
    public var user: User
    public var roleName: String
    public var rolePosition: Int?
    public var isRoleCategory: Bool?
    public var status: PresenceStatus
    public var roles: [GuildRole]
    public var guildAvatarURL: URL?
    public var activityText: String?
    public var customStatus: String?

    public var isOnline: Bool { status.isVisibleOnline }

    public init(
        user: User,
        roleName: String,
        isOnline: Bool,
        rolePosition: Int? = nil,
        isRoleCategory: Bool? = nil,
        roles: [GuildRole] = [],
        guildAvatarURL: URL? = nil,
        activityText: String? = nil,
        customStatus: String? = nil
    ) {
        self.user = user
        self.roleName = roleName
        self.rolePosition = rolePosition
        self.isRoleCategory = isRoleCategory
        self.status = isOnline ? .online : .offline
        self.roles = roles
        self.guildAvatarURL = guildAvatarURL
        self.activityText = activityText
        self.customStatus = customStatus
    }

    public init(
        user: User,
        roleName: String,
        status: PresenceStatus,
        rolePosition: Int? = nil,
        isRoleCategory: Bool? = nil,
        roles: [GuildRole] = [],
        guildAvatarURL: URL? = nil,
        activityText: String? = nil,
        customStatus: String? = nil
    ) {
        self.user = user
        self.roleName = roleName
        self.rolePosition = rolePosition
        self.isRoleCategory = isRoleCategory
        self.status = status
        self.roles = roles
        self.guildAvatarURL = guildAvatarURL
        self.activityText = activityText
        self.customStatus = customStatus
    }

    private enum CodingKeys: String, CodingKey {
        case user, roleName, rolePosition, isRoleCategory, status, roles, guildAvatarURL, activityText, customStatus
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        user = try container.decode(User.self, forKey: .user)
        roleName = try container.decodeIfPresent(String.self, forKey: .roleName) ?? "Member"
        rolePosition = try container.decodeIfPresent(Int.self, forKey: .rolePosition)
        isRoleCategory = try container.decodeIfPresent(Bool.self, forKey: .isRoleCategory)
        status = try container.decodeIfPresent(PresenceStatus.self, forKey: .status) ?? .offline
        roles = try container.decodeIfPresent([GuildRole].self, forKey: .roles) ?? []
        guildAvatarURL = try container.decodeIfPresent(URL.self, forKey: .guildAvatarURL)
        activityText = try container.decodeIfPresent(String.self, forKey: .activityText)
        customStatus = try container.decodeIfPresent(String.self, forKey: .customStatus)
    }
}

public struct ProfileBadge: Identifiable, Codable, Hashable, Sendable {
    public let id: String
    public var description: String
    public var iconURL: URL?
    public var linkURL: URL?

    public init(id: String, description: String, iconURL: URL? = nil, linkURL: URL? = nil) {
        self.id = id
        self.description = description
        self.iconURL = iconURL
        self.linkURL = linkURL
    }
}

public struct ProfileEffect: Identifiable, Codable, Hashable, Sendable {
    public let id: String
    public var title: String?
    public var accessibilityLabel: String?
    public var staticURL: URL?
    public var reducedMotionURL: URL?
    public var animations: [ProfileEffectAnimation]

    public init(
        id: String,
        title: String? = nil,
        accessibilityLabel: String? = nil,
        staticURL: URL? = nil,
        reducedMotionURL: URL? = nil,
        animations: [ProfileEffectAnimation] = []
    ) {
        self.id = id
        self.title = title
        self.accessibilityLabel = accessibilityLabel
        self.staticURL = staticURL
        self.reducedMotionURL = reducedMotionURL
        self.animations = animations
    }

    private enum CodingKeys: String, CodingKey {
        case id, title, accessibilityLabel, staticURL, reducedMotionURL, animations
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        title = try container.decodeIfPresent(String.self, forKey: .title)
        accessibilityLabel = try container.decodeIfPresent(String.self, forKey: .accessibilityLabel)
        staticURL = try container.decodeIfPresent(URL.self, forKey: .staticURL)
        reducedMotionURL = try container.decodeIfPresent(URL.self, forKey: .reducedMotionURL)
        animations = try container.decodeIfPresent([ProfileEffectAnimation].self, forKey: .animations) ?? []
    }
}

public struct ProfileEffectAnimation: Identifiable, Codable, Hashable, Sendable {
    public var id: String { "\(sourceURL.absoluteString):\(startMilliseconds):\(zIndex)" }
    public var sourceURL: URL
    public var isLooping: Bool
    public var width: Int?
    public var height: Int?
    public var durationMilliseconds: Int
    public var startMilliseconds: Int
    public var loopDelayMilliseconds: Int
    public var positionX: Int
    public var positionY: Int
    public var zIndex: Int

    public init(
        sourceURL: URL,
        isLooping: Bool = true,
        width: Int? = nil,
        height: Int? = nil,
        durationMilliseconds: Int = 0,
        startMilliseconds: Int = 0,
        loopDelayMilliseconds: Int = 0,
        positionX: Int = 0,
        positionY: Int = 0,
        zIndex: Int = 0
    ) {
        self.sourceURL = sourceURL
        self.isLooping = isLooping
        self.width = width
        self.height = height
        self.durationMilliseconds = durationMilliseconds
        self.startMilliseconds = startMilliseconds
        self.loopDelayMilliseconds = loopDelayMilliseconds
        self.positionX = positionX
        self.positionY = positionY
        self.zIndex = zIndex
    }
}

public struct MutualGuild: Identifiable, Codable, Hashable, Sendable {
    public let id: GuildID
    public var name: String
    public var iconURL: URL?
    public var nickname: String?

    public init(id: GuildID, name: String, iconURL: URL? = nil, nickname: String? = nil) {
        self.id = id
        self.name = name
        self.iconURL = iconURL
        self.nickname = nickname
    }
}

public struct ConnectedAccount: Identifiable, Codable, Hashable, Sendable {
    public var id: String { "\(type):\(accountID)" }
    public var accountID: String
    public var type: String
    public var name: String
    public var isVerified: Bool
    public var profileURL: URL?

    public init(accountID: String, type: String, name: String, isVerified: Bool = false, profileURL: URL? = nil) {
        self.accountID = accountID
        self.type = type
        self.name = name
        self.isVerified = isVerified
        self.profileURL = profileURL
    }
}

public struct UserProfile: Identifiable, Codable, Hashable, Sendable {
    public var id: UserID { user.id }
    public var user: User
    public var displayName: String
    public var avatarURL: URL?
    public var bannerURL: URL?
    public var accentHex: UInt32?
    public var themeHexes: [UInt32]
    public var bio: String?
    public var pronouns: String?
    public var effect: ProfileEffect?
    public var badges: [ProfileBadge]
    public var mutualGuilds: [MutualGuild]
    public var mutualFriends: [User]
    public var mutualFriendsCount: Int
    public var roles: [GuildRole]
    public var connectedAccounts: [ConnectedAccount]
    public var premiumSince: Date?
    public var premiumGuildSince: Date?
    public var legacyUsername: String?
    public var status: PresenceStatus
    public var customStatus: String?

    public init(
        user: User,
        displayName: String? = nil,
        avatarURL: URL? = nil,
        bannerURL: URL? = nil,
        accentHex: UInt32? = nil,
        themeHexes: [UInt32] = [],
        bio: String? = nil,
        pronouns: String? = nil,
        effect: ProfileEffect? = nil,
        badges: [ProfileBadge] = [],
        mutualGuilds: [MutualGuild] = [],
        mutualFriends: [User] = [],
        mutualFriendsCount: Int = 0,
        roles: [GuildRole] = [],
        connectedAccounts: [ConnectedAccount] = [],
        premiumSince: Date? = nil,
        premiumGuildSince: Date? = nil,
        legacyUsername: String? = nil,
        status: PresenceStatus = .offline,
        customStatus: String? = nil
    ) {
        self.user = user
        self.displayName = displayName ?? user.displayName
        self.avatarURL = avatarURL ?? user.avatarURL
        self.bannerURL = bannerURL
        self.accentHex = accentHex
        self.themeHexes = themeHexes
        self.bio = bio
        self.pronouns = pronouns
        self.effect = effect
        self.badges = badges
        self.mutualGuilds = mutualGuilds
        self.mutualFriends = mutualFriends
        self.mutualFriendsCount = mutualFriendsCount
        self.roles = roles
        self.connectedAccounts = connectedAccounts
        self.premiumSince = premiumSince
        self.premiumGuildSince = premiumGuildSince
        self.legacyUsername = legacyUsername
        self.status = status
        self.customStatus = customStatus
    }
}

public struct BootstrapSnapshot: Codable, Equatable, Sendable {
    public var currentUser: User
    public var guilds: [Guild]
    public var channels: [Channel]
    public var members: [Member]

    public init(currentUser: User, guilds: [Guild], channels: [Channel], members: [Member]) {
        self.currentUser = currentUser
        self.guilds = guilds
        self.channels = channels
        self.members = members
    }
}

public struct MessagePage: Codable, Equatable, Sendable {
    public var messages: [Message]
    public var hasMoreBefore: Bool

    public init(messages: [Message], hasMoreBefore: Bool) {
        self.messages = messages
        self.hasMoreBefore = hasMoreBefore
    }
}

public struct SendMessageDraft: Equatable, Sendable {
    public var channelID: ChannelID
    public var content: String
    public var replyTo: MessageID?
    public var attachmentURLs: [URL]
    public var nonce: String

    public init(channelID: ChannelID, content: String, replyTo: MessageID? = nil, attachmentURLs: [URL] = [], nonce: String = ClientNonce.make()) {
        self.channelID = channelID
        self.content = content
        self.replyTo = replyTo
        self.attachmentURLs = attachmentURLs
        self.nonce = nonce
    }
}

public struct VoiceConnectionInfo: Equatable, Sendable {
    public var serverID: String
    public var channelID: ChannelID
    public var guildID: GuildID?
    public var userID: UserID
    public var sessionID: String
    public var token: String
    public var endpoint: String

    public init(
        serverID: String,
        channelID: ChannelID,
        guildID: GuildID?,
        userID: UserID,
        sessionID: String,
        token: String,
        endpoint: String
    ) {
        self.serverID = serverID
        self.channelID = channelID
        self.guildID = guildID
        self.userID = userID
        self.sessionID = sessionID
        self.token = token
        self.endpoint = endpoint
    }
}

public struct VoiceParticipantState: Equatable, Sendable {
    public var userID: UserID
    public var channelID: ChannelID?
    public var guildID: GuildID?
    public var sessionID: String
    public var isMuted: Bool
    public var isDeafened: Bool
    public var isSelfMuted: Bool
    public var isSelfDeafened: Bool
    public var isSuppressed: Bool
    public var isStreaming: Bool
    public var isVideoEnabled: Bool

    public init(
        userID: UserID,
        channelID: ChannelID?,
        guildID: GuildID?,
        sessionID: String,
        isMuted: Bool = false,
        isDeafened: Bool = false,
        isSelfMuted: Bool = false,
        isSelfDeafened: Bool = false,
        isSuppressed: Bool = false,
        isStreaming: Bool = false,
        isVideoEnabled: Bool = false
    ) {
        self.userID = userID
        self.channelID = channelID
        self.guildID = guildID
        self.sessionID = sessionID
        self.isMuted = isMuted
        self.isDeafened = isDeafened
        self.isSelfMuted = isSelfMuted
        self.isSelfDeafened = isSelfDeafened
        self.isSuppressed = isSuppressed
        self.isStreaming = isStreaming
        self.isVideoEnabled = isVideoEnabled
    }
}

public enum ClientNonce {
    /// Discord message nonces use the same timestamp layout as snowflakes.
    /// The upper 42 bits are milliseconds since Discord's 2015 epoch, not Unix
    /// milliseconds. A local 12-bit sequence keeps multiple messages created in
    /// the same millisecond distinct without fabricating worker or process IDs.
    public static let discordEpochMilliseconds: UInt64 = 1_420_070_400_000
    private static let sequenceState = Mutex((millisecond: UInt64(0), sequence: UInt16(0)))

    public static func make(now: Date = .now) -> String {
        let milliseconds = UInt64(max(0, now.timeIntervalSince1970 * 1_000))
        guard milliseconds >= discordEpochMilliseconds else { return "0" }
        let sequence = sequenceState.withLock { state -> UInt16 in
            if state.millisecond == milliseconds {
                state.sequence = (state.sequence + 1) & 0x0FFF
            } else {
                state.millisecond = milliseconds
                state.sequence = 0
            }
            return state.sequence
        }
        return String(((milliseconds - discordEpochMilliseconds) << 22) | UInt64(sequence))
    }
}

public enum ConnectionState: String, Codable, Equatable, Sendable {
    case disconnected, connecting, ready, resuming, backingOff, authenticationFailed
}

public enum ClientEvent: Equatable, Sendable {
    case connectionChanged(ConnectionState)
    case messageCreated(Message)
    case messageUpdated(Message)
    case messageDeleted(channelID: ChannelID, messageID: MessageID)
    case typing(channelID: ChannelID, user: User)
    case membersChanged(guildID: GuildID, members: [Member])
    case voiceStateChanged(VoiceParticipantState)
    /// A nil value means Discord deallocated the current voice server and the
    /// client must wait for a replacement allocation before reconnecting.
    case voiceServerChanged(VoiceConnectionInfo?)
    case snapshotChanged(BootstrapSnapshot)
}
