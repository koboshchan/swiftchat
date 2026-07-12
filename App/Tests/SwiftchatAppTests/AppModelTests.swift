import Testing
import DiscordProtocol
import SwiftchatModels
import Foundation
@testable import Swiftchat

@MainActor
@Test func appModelLoadsDemoAndSendsMessage() async {
    let model = AppModel(restoreStoredSession: false)
    await model.start()
    #expect(model.snapshot != nil)
    #expect(model.selectedChannel != nil)
    let before = model.messages.count
    model.updateDraft("hello from test")
    await model.send()
    #expect(model.messages.count == before + 1)
    #expect(model.messages.last?.content == "hello from test")
}

@MainActor
@Test func replyingTargetsTheSelectedMessageAndClearsAfterSending() async throws {
    let model = AppModel(restoreStoredSession: false)
    await model.start()
    let target = try #require(model.messages.first)

    model.reply(to: target)
    #expect(model.replyingTo?.id == target.id)

    model.updateDraft("reply from test")
    await model.send()

    #expect(model.messages.last?.replyTo == target.id)
    #expect(model.messageRows.last?.replyPreview?.messageID == target.id)
    #expect(model.messageRows.last?.replyPreview?.content == target.content)
    #expect(model.replyingTo == nil)
}

@MainActor
@Test func messageGroupingMatchesDiscordContinuationRules() {
    let author = User(id: UserID(rawValue: 1), username: "one", displayName: "One")
    let other = User(id: UserID(rawValue: 2), username: "two", displayName: "Two")
    let channel = ChannelID(rawValue: 10)
    let base = Date(timeIntervalSince1970: 1_700_000_000)
    let messages = [
        Message(id: MessageID(rawValue: 1), channelID: channel, author: author, content: "first", timestamp: base),
        Message(id: MessageID(rawValue: 2), channelID: channel, author: author, content: "six minutes", timestamp: base.addingTimeInterval(6 * 60)),
        Message(id: MessageID(rawValue: 3), channelID: channel, author: author, content: "seven minutes", timestamp: base.addingTimeInterval(13 * 60)),
        Message(id: MessageID(rawValue: 4), channelID: channel, author: other, content: "other author", timestamp: base.addingTimeInterval(13 * 60 + 1)),
        Message(id: MessageID(rawValue: 5), channelID: channel, author: other, content: "reply", timestamp: base.addingTimeInterval(13 * 60 + 2), replyTo: MessageID(rawValue: 1)),
    ]

    let rows = MessageGrouping.rows(for: messages)
    #expect(rows.map { $0.startsGroup } == [true, false, true, true, true])
}

@MainActor
@Test func memberSectionsUseHoistedRolesAndSortMembers() {
    let members = [
        Member(
            user: User(id: UserID(rawValue: 1), username: "zed", displayName: "Zed"),
            roleName: "Moderator",
            status: .online,
            rolePosition: 10,
            isRoleCategory: true
        ),
        Member(
            user: User(id: UserID(rawValue: 2), username: "amy", displayName: "Amy"),
            roleName: "Moderator",
            status: .idle,
            rolePosition: 10,
            isRoleCategory: true
        ),
        Member(
            user: User(id: UserID(rawValue: 3), username: "sam", displayName: "Sam"),
            roleName: "Member",
            status: .online
        ),
        Member(
            user: User(id: UserID(rawValue: 4), username: "off", displayName: "Offline"),
            roleName: "Moderator",
            status: .offline,
            rolePosition: 10,
            isRoleCategory: true
        ),
    ]

    let sections = MemberSection.make(from: members)
    #expect(sections.map(\.title) == ["Moderator", "Online", "Offline"])
    #expect(sections[0].members.map(\.user.displayName) == ["Amy", "Zed"])
    #expect(sections[2].members.map(\.user.displayName) == ["Offline"])
}

@MainActor
@Test func channelGroupsPlaceVoiceChannelsAfterTextChannels() {
    let guildID = GuildID(rawValue: 20)
    let categoryID = ChannelID(rawValue: 21)
    let channels = [
        Channel(id: ChannelID(rawValue: 22), guildID: guildID, name: "Voice first by position", kind: .voice, category: "Chat", categoryID: categoryID, position: 0),
        Channel(id: ChannelID(rawValue: 23), guildID: guildID, name: "general", category: "Chat", categoryID: categoryID, position: 2),
        Channel(id: ChannelID(rawValue: 24), guildID: guildID, name: "announcements", kind: .announcement, category: "Chat", categoryID: categoryID, position: 3),
        Channel(id: ChannelID(rawValue: 25), guildID: guildID, name: "Voice second", kind: .voice, category: "Chat", categoryID: categoryID, position: 1),
    ]

    let group = ChannelGroup.make(from: channels)[0]
    #expect(group.channels.map(\.name) == ["general", "announcements", "Voice first by position", "Voice second"])
}

@MainActor
@Test func selectingVoiceChannelNavigatesWithoutJoiningOrLoadingMessages() async throws {
    let model = AppModel(restoreStoredSession: false)
    await model.start()
    let voiceChannel = try #require(model.visibleChannels.first(where: { $0.kind == .voice }))

    model.selectedChannelID = voiceChannel.id

    #expect(model.selectedChannel?.id == voiceChannel.id)
    #expect(model.selectedChannel?.kind == .voice)
    #expect(model.activeVoiceChannel == nil)
    #expect(model.messages.isEmpty)
    #expect(!model.isLoadingMessages)
}

@MainActor
@Test func profileRoleNamesRemoveCustomEmojiMarkupAndCollapseWhitespace() {
    #expect(
        ProfileRolePresentation.normalizedName("  Developers   <:sparkle:123456>   💖  ")
            == "Developers 💖"
    )
    #expect(ProfileRolePresentation.normalizedName("<a:dance:987654>") == "")
    #expect(ProfileRolePresentation.collapsedLimit == 5)
}

@MainActor
@Test func selectingMemberLoadsFullProfile() async throws {
    let model = AppModel(restoreStoredSession: false)
    await model.start()
    let member = try #require(model.members.first)

    model.selectMember(member)
    try await Task.sleep(for: .milliseconds(20))

    let profile = try #require(model.selectedProfile)
    #expect(profile.id == member.id)
    #expect(!profile.badges.isEmpty)
    #expect(!profile.mutualGuilds.isEmpty)
    #expect(profile.status == member.status)
}

@MainActor
@Test func channelLoadsAreSingleFlightCachedAndProtectedFromStaleResponses() async throws {
    let provider = ChannelLoadTestProvider()
    let model = AppModel(provider: provider, restoreStoredSession: false)

    await model.start()
    let firstChannel = ChannelID(rawValue: 91_001)
    let secondChannel = ChannelID(rawValue: 91_002)
    #expect(await provider.requestCount(for: firstChannel) == 1)
    #expect(model.messages.map(\.channelID) == [firstChannel])

    model.selectedChannelID = secondChannel
    try await Task.sleep(for: .milliseconds(5))
    model.selectedChannelID = firstChannel

    // The in-memory page is restored synchronously, before either refresh finishes.
    #expect(model.messages.map(\.channelID) == [firstChannel])
    try await Task.sleep(for: .milliseconds(160))

    #expect(model.selectedChannelID == firstChannel)
    #expect(model.messages.allSatisfy { $0.channelID == firstChannel })
    #expect(await provider.requestCount(for: firstChannel) == 2)
    #expect(await provider.requestCount(for: secondChannel) == 1)
}

@MainActor
@Test func voiceServerReallocationKeepsTheCallSelectedAndReconnects() async throws {
    let provider = VoiceMigrationTestProvider()
    let model = AppModel(provider: provider, restoreStoredSession: false)
    await model.start()
    let voiceChannel = try #require(model.visibleChannels.first)

    await model.joinVoice(voiceChannel)
    #expect(model.activeVoiceChannel?.id == voiceChannel.id)
    #expect(model.voiceSessionState == .connected)

    await provider.emit(.voiceServerChanged(nil))
    try await Task.sleep(for: .milliseconds(20))
    #expect(model.activeVoiceChannel?.id == voiceChannel.id)
    #expect(model.voiceSessionState == .reconnecting)

    await provider.emit(.voiceServerChanged(await provider.connectionInfo(token: "replacement")))
    try await Task.sleep(for: .milliseconds(20))
    #expect(model.activeVoiceChannel?.id == voiceChannel.id)
    #expect(model.voiceSessionState == .connected)
}

private actor ChannelLoadTestProvider: ChatProvider {
    private let user = User(id: UserID(rawValue: 91_000), username: "tester", displayName: "Tester")
    private let testChannels = [
        Channel(id: ChannelID(rawValue: 91_001), guildID: nil, name: "general"),
        Channel(id: ChannelID(rawValue: 91_002), guildID: nil, name: "other"),
    ]
    private var messageRequests: [ChannelID: Int] = [:]

    func bootstrap() async throws -> BootstrapSnapshot {
        BootstrapSnapshot(currentUser: user, guilds: [], channels: testChannels, members: [])
    }

    func channels(in guildID: GuildID?) async throws -> [Channel] { testChannels }
    func members(in guildID: GuildID?) async throws -> [Member] { [] }
    func profile(for userID: UserID, in guildID: GuildID?) async throws -> UserProfile {
        throw ChatProviderError.invalidRequest("Profiles are not part of this test.")
    }
    func currentStatus() async -> PresenceStatus { .online }
    func updateStatus(_ status: PresenceStatus) async throws {}

    func messages(in channelID: ChannelID, before: MessageID?, limit: Int) async throws -> MessagePage {
        messageRequests[channelID, default: 0] += 1
        // Intentionally ignore cancellation to prove the model's generation guard works.
        let delay: Duration = channelID == testChannels[1].id ? .milliseconds(100) : .milliseconds(20)
        try? await Task.sleep(for: delay)
        let message = Message(
            id: MessageID(rawValue: channelID.rawValue),
            channelID: channelID,
            author: user,
            content: "channel \(channelID)"
        )
        return MessagePage(messages: [message], hasMoreBefore: false)
    }

    func send(_ draft: SendMessageDraft) async throws -> Message {
        throw ChatProviderError.invalidRequest("Sending is not part of this test.")
    }
    func edit(messageID: MessageID, channelID: ChannelID, content: String) async throws -> Message {
        throw ChatProviderError.invalidRequest("Editing is not part of this test.")
    }
    func delete(messageID: MessageID, channelID: ChannelID) async throws {}
    func toggleReaction(_ emoji: String, messageID: MessageID, channelID: ChannelID) async throws {}
    func eventStream() async -> AsyncStream<ClientEvent> { AsyncStream { $0.finish() } }
    func disconnect() async {}

    func requestCount(for channelID: ChannelID) -> Int { messageRequests[channelID, default: 0] }
}

private actor VoiceMigrationTestProvider: ChatProvider {
    private let guild = Guild(id: GuildID(rawValue: 92_000), name: "Voice Test")
    private let user = User(id: UserID(rawValue: 92_001), username: "tester", displayName: "Tester")
    private let channel = Channel(
        id: ChannelID(rawValue: 92_002),
        guildID: GuildID(rawValue: 92_000),
        name: "Lounge",
        kind: .voice
    )
    private var continuation: AsyncStream<ClientEvent>.Continuation?

    func bootstrap() async throws -> BootstrapSnapshot {
        BootstrapSnapshot(currentUser: user, guilds: [guild], channels: [channel], members: [])
    }

    func channels(in guildID: GuildID?) async throws -> [Channel] { [channel] }
    func members(in guildID: GuildID?) async throws -> [Member] { [] }
    func profile(for userID: UserID, in guildID: GuildID?) async throws -> UserProfile {
        throw ChatProviderError.invalidRequest("Profiles are not part of this test.")
    }
    func currentStatus() async -> PresenceStatus { .online }
    func updateStatus(_ status: PresenceStatus) async throws {}
    func messages(in channelID: ChannelID, before: MessageID?, limit: Int) async throws -> MessagePage {
        MessagePage(messages: [], hasMoreBefore: false)
    }
    func send(_ draft: SendMessageDraft) async throws -> Message {
        throw ChatProviderError.invalidRequest("Sending is not part of this test.")
    }
    func edit(messageID: MessageID, channelID: ChannelID, content: String) async throws -> Message {
        throw ChatProviderError.invalidRequest("Editing is not part of this test.")
    }
    func delete(messageID: MessageID, channelID: ChannelID) async throws {}
    func toggleReaction(_ emoji: String, messageID: MessageID, channelID: ChannelID) async throws {}
    func joinVoice(
        channelID: ChannelID,
        guildID: GuildID?,
        selfMute: Bool,
        selfDeaf: Bool
    ) async throws -> VoiceConnectionInfo {
        connectionInfo(token: "initial")
    }
    func updateVoiceState(
        channelID: ChannelID?,
        guildID: GuildID?,
        selfMute: Bool,
        selfDeaf: Bool,
        selfVideo: Bool
    ) async throws {}
    func eventStream() async -> AsyncStream<ClientEvent> {
        AsyncStream { continuation = $0 }
    }
    func disconnect() async {
        continuation?.finish()
        continuation = nil
    }

    func emit(_ event: ClientEvent) {
        continuation?.yield(event)
    }

    func connectionInfo(token: String) -> VoiceConnectionInfo {
        VoiceConnectionInfo(
            serverID: guild.id.description,
            channelID: channel.id,
            guildID: guild.id,
            userID: user.id,
            sessionID: "session",
            token: token,
            endpoint: "mock.swiftchat.invalid"
        )
    }
}
