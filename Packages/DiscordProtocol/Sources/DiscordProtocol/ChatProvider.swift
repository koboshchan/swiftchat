import Foundation
import SwiftchatModels

public protocol ChatProvider: Sendable {
    func bootstrap() async throws -> BootstrapSnapshot
    func channels(in guildID: GuildID?) async throws -> [Channel]
    func members(in guildID: GuildID?) async throws -> [Member]
    func profile(for userID: UserID, in guildID: GuildID?) async throws -> UserProfile
    func emojis(in guildID: GuildID) async throws -> [DiscordEmoji]
    func emojiUserSettings() async throws -> EmojiUserSettings
    func currentStatus() async -> PresenceStatus
    func updateStatus(_ status: PresenceStatus) async throws
    func messages(in channelID: ChannelID, before: MessageID?, limit: Int) async throws -> MessagePage
    func sendTyping(in channelID: ChannelID) async throws
    func send(_ draft: SendMessageDraft) async throws -> Message
    func edit(messageID: MessageID, channelID: ChannelID, content: String) async throws -> Message
    func delete(messageID: MessageID, channelID: ChannelID) async throws
    func toggleReaction(_ emoji: String, messageID: MessageID, channelID: ChannelID) async throws
    func joinVoice(
        channelID: ChannelID,
        guildID: GuildID?,
        selfMute: Bool,
        selfDeaf: Bool
    ) async throws -> VoiceConnectionInfo
    func updateVoiceState(
        channelID: ChannelID?,
        guildID: GuildID?,
        selfMute: Bool,
        selfDeaf: Bool,
        selfVideo: Bool
    ) async throws
    func eventStream() async -> AsyncStream<ClientEvent>
    func disconnect() async
}

public extension ChatProvider {
    func emojis(in guildID: GuildID) async throws -> [DiscordEmoji] {
        []
    }

    func emojiUserSettings() async throws -> EmojiUserSettings {
        EmojiUserSettings()
    }

    func sendTyping(in channelID: ChannelID) async throws {}

    func joinVoice(
        channelID: ChannelID,
        guildID: GuildID?,
        selfMute: Bool,
        selfDeaf: Bool
    ) async throws -> VoiceConnectionInfo {
        throw ChatProviderError.invalidRequest("Voice calling is unavailable for this provider.")
    }

    func updateVoiceState(
        channelID: ChannelID?,
        guildID: GuildID?,
        selfMute: Bool,
        selfDeaf: Bool,
        selfVideo: Bool
    ) async throws {
        throw ChatProviderError.invalidRequest("Voice calling is unavailable for this provider.")
    }

    func updateVoiceState(
        channelID: ChannelID?,
        guildID: GuildID?,
        selfMute: Bool,
        selfDeaf: Bool
    ) async throws {
        try await updateVoiceState(
            channelID: channelID,
            guildID: guildID,
            selfMute: selfMute,
            selfDeaf: selfDeaf,
            selfVideo: false
        )
    }
}

public enum ChatProviderError: LocalizedError, Equatable, Sendable {
    case unauthenticated
    case channelNotFound
    case messageNotFound
    case invalidRequest(String)
    case transport(status: Int, requestID: String?)

    public var errorDescription: String? {
        switch self {
        case .unauthenticated: "The account session is no longer valid."
        case .channelNotFound: "The selected channel is unavailable."
        case .messageNotFound: "The message no longer exists."
        case let .invalidRequest(message): message
        case let .transport(status, requestID):
            requestID.map { "Discord returned HTTP \(status) (request \($0))." } ?? "Discord returned HTTP \(status)."
        }
    }
}
