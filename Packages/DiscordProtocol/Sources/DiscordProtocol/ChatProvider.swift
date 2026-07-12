import SwiftchatModels
import Foundation

public protocol ChatProvider: Sendable {
    func bootstrap() async throws -> BootstrapSnapshot
    func channels(in guildID: GuildID?) async throws -> [Channel]
    func members(in guildID: GuildID?) async throws -> [Member]
    func profile(for userID: UserID, in guildID: GuildID?) async throws -> UserProfile
    func currentStatus() async -> PresenceStatus
    func updateStatus(_ status: PresenceStatus) async throws
    func messages(in channelID: ChannelID, before: MessageID?, limit: Int) async throws -> MessagePage
    func send(_ draft: SendMessageDraft) async throws -> Message
    func edit(messageID: MessageID, channelID: ChannelID, content: String) async throws -> Message
    func delete(messageID: MessageID, channelID: ChannelID) async throws
    func toggleReaction(_ emoji: String, messageID: MessageID, channelID: ChannelID) async throws
    func eventStream() async -> AsyncStream<ClientEvent>
    func disconnect() async
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
