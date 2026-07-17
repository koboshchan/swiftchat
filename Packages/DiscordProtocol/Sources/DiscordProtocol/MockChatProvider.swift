import Foundation
import SwiftchatModels
import UniformTypeIdentifiers

public actor MockChatProvider: ChatProvider {
    private let currentUser: User
    private var snapshot: BootstrapSnapshot
    private var membersByGuild: [GuildID: [Member]]
    private var messagesByChannel: [ChannelID: [Message]]
    private var profilesByUser: [UserID: UserProfile]
    private var continuation: AsyncStream<ClientEvent>.Continuation?
    private var nextMessageID: UInt64
    public private(set) var typingRequests: [ChannelID] = []

    public init(includesLongServerList: Bool = false) {
        let fixture = MockChatFixture.make(includesLongServerList: includesLongServerList)
        currentUser = fixture.currentUser
        nextMessageID = UInt64(ClientNonce.make()) ?? 9000
        snapshot = fixture.snapshot
        membersByGuild = fixture.membersByGuild
        messagesByChannel = fixture.messagesByChannel
        profilesByUser = fixture.profilesByUser
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

    public func members(in guildID: GuildID?) async throws -> [Member] {
        guard let guildID else { return [Member(user: currentUser, roleName: "You", status: .online)] }
        return membersByGuild[guildID] ?? []
    }

    public func emojis(in guildID: GuildID) async throws -> [DiscordEmoji] {
        []
    }

    public func profile(for userID: UserID, in guildID: GuildID?) async throws -> UserProfile {
        guard let profile = profilesByUser[userID] else {
            throw ChatProviderError.invalidRequest("That demo profile is unavailable.")
        }
        return profile
    }

    public func currentStatus() async -> PresenceStatus {
        .online
    }

    public func updateStatus(_ status: PresenceStatus) async throws {
        for guildID in Array(membersByGuild.keys) {
            membersByGuild[guildID] = membersByGuild[guildID]?.map { member in
                guard member.user.id == snapshot.currentUser.id else { return member }
                var updatedMember = member
                updatedMember.status = status
                return updatedMember
            }
        }
        snapshot.members = membersByGuild[snapshot.guilds.first?.id ?? GuildID(rawValue: 0)] ?? snapshot.members
        if var profile = profilesByUser[currentUser.id] {
            profile.status = status
            profilesByUser[currentUser.id] = profile
        }
        continuation?.yield(.snapshotChanged(snapshot))
    }

    public func messages(in channelID: ChannelID, before: MessageID?, limit: Int) async throws -> MessagePage {
        guard snapshot.channels.contains(where: { $0.id == channelID }) else { throw ChatProviderError.channelNotFound }
        var messages = messagesByChannel[channelID] ?? []
        if let before {
            messages = messages.filter { $0.id < before }
        }
        let page = Array(messages.suffix(max(1, limit)))
        return MessagePage(messages: page, hasMoreBefore: messages.count > page.count)
    }

    public func sendTyping(in channelID: ChannelID) async throws {
        guard let channel = snapshot.channels.first(where: { $0.id == channelID }) else {
            throw ChatProviderError.channelNotFound
        }
        guard channel.kind != .voice, channel.kind != .forum, channel.kind != .unknown else {
            throw ChatProviderError.invalidRequest("Typing is unavailable in this demo channel.")
        }
        typingRequests.append(channelID)
    }

    public func send(_ draft: SendMessageDraft) async throws -> Message {
        guard !draft.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !draft.attachmentURLs.isEmpty else {
            throw ChatProviderError.invalidRequest("A message needs text or an attachment.")
        }
        nextMessageID += 1
        let attachments = try draft.attachmentURLs.enumerated().map { index, url in
            try Self.stageAttachment(url, messageID: nextMessageID, index: index)
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

    private static func stageAttachment(_ sourceURL: URL, messageID: UInt64, index: Int) throws -> Attachment {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "SwiftchatDemoAttachments", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let fileExtension = sourceURL.pathExtension
        let filename = sourceURL.lastPathComponent.isEmpty ? "attachment-\(index)" : sourceURL.lastPathComponent
        let destination = directory.appending(
            path: "\(messageID)-\(index)\(fileExtension.isEmpty ? "" : ".\(fileExtension)")"
        )
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.copyItem(at: sourceURL, to: destination)
        let values = try destination.resourceValues(forKeys: [.fileSizeKey])
        let mediaType = UTType(filenameExtension: fileExtension)?.preferredMIMEType
        return Attachment(
            id: "\(messageID)-\(index)",
            filename: filename,
            url: destination,
            mediaType: mediaType,
            size: values.fileSize ?? 0
        )
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
            if message.reactions[reactionIndex].count == 0 {
                message.reactions.remove(at: reactionIndex)
            }
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
