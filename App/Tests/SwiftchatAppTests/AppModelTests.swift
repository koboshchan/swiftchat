import Testing
import DiscordProtocol
import SwiftchatModels
import Foundation
@testable import Swiftchat

@MainActor
@Test func nativeEmojiCatalogLoadsEveryFullyQualifiedUnicode17Emoji() {
    #expect(NativeEmojiCatalogDiagnostics.sourceEntryCount == 3_944)
    #expect(NativeEmojiCatalogDiagnostics.itemCount < NativeEmojiCatalogDiagnostics.sourceEntryCount)
    #expect(NativeEmojiCatalogDiagnostics.skinToneCapableItemCount > 100)
    #expect(NativeEmojiCatalogDiagnostics.wavingHandValues == ["👋", "👋🏻", "👋🏼", "👋🏽", "👋🏾", "👋🏿"])
    #expect(NativeEmojiCatalogDiagnostics.mediumToneVariationSelectorValues == ["✌🏽", "☝🏽", "✍🏽"])
    #expect(NativeEmojiCatalogDiagnostics.baseItemsContainingSkinToneModifier == 0)
    #expect(NativeEmojiCatalogDiagnostics.categoryItemCounts.count == 9)
    #expect(NativeEmojiCatalogDiagnostics.categoryItemCounts.values.allSatisfy { $0 > 0 })
    #expect(NativeEmojiCatalogDiagnostics.shortcode(for: "🤍") == ":white_heart:")
    // Tone variants share their base emoji's aliases, so the collapsed picker catalog is smaller
    // than Emojibase's 3,808 keyed source records.
    #expect(NativeEmojiCatalogDiagnostics.emojiCountWithDiscordShortcodes == 1_884)
    #expect(NativeEmojiCatalogDiagnostics.discordShortcodeAliasCount == 2_551)
    #expect(NativeEmojiCatalogDiagnostics.shortcodes(for: "🎉") == ["tada", "party_popper"])
    #expect(NativeEmojiCatalogDiagnostics.shortcode(for: "🎉") == ":tada:")
    #expect(NativeEmojiCatalogDiagnostics.searchMatches(value: "🎉", query: ":party_popper:"))
    #expect(NativeEmojiCatalogDiagnostics.searchMatches(value: "👍", query: "+1"))
    #expect(EmojiSearchMatcher.normalized(":grinning_face:") == "grinning_face")
}

@MainActor
@Test func emojiPickerUsesOneContinuousRecycledDocument() {
    #expect(EmojiPickerPerformanceDiagnostics.itemsPerRecycledRow == 9)
    #expect(EmojiPickerPerformanceDiagnostics.nativeSectionIDs.count == 9)
    #expect(Set(EmojiPickerPerformanceDiagnostics.nativeSectionIDs).count == 9)
    #expect(EmojiPickerPerformanceDiagnostics.nativeDocumentRowCount
        < EmojiPickerPerformanceDiagnostics.nativeItemCount / 4)
    #expect(NativeEmojiCatalogDiagnostics.categoryItemCounts["people", default: 0] > 300)
    #expect(!EmojiPickerPerformanceDiagnostics.nativeSidebarIsVisible(
        bounds: nil,
        viewportHeight: 300
    ))
    #expect(!EmojiPickerPerformanceDiagnostics.nativeSidebarIsVisible(
        bounds: CGRect(x: 0, y: 320, width: 46, height: 300),
        viewportHeight: 300
    ))
    #expect(EmojiPickerPerformanceDiagnostics.nativeSidebarIsVisible(
        bounds: CGRect(x: 0, y: 280, width: 46, height: 300),
        viewportHeight: 300
    ))
}

@Test func emojiPickerKeyboardNavigationWrapsRowsAndClampsColumns() {
    let rows = [
        ["a", "b", "c"],
        ["d", "e", "f"],
        ["g"],
    ]

    #expect(EmojiPickerGridNavigation.destinationID(
        rows: rows, currentID: nil, direction: .right
    ) == "a")
    #expect(EmojiPickerGridNavigation.destinationID(
        rows: rows, currentID: "a", direction: .left
    ) == "a")
    #expect(EmojiPickerGridNavigation.destinationID(
        rows: rows, currentID: "c", direction: .right
    ) == "d")
    #expect(EmojiPickerGridNavigation.destinationID(
        rows: rows, currentID: "d", direction: .left
    ) == "c")
    #expect(EmojiPickerGridNavigation.destinationID(
        rows: rows, currentID: "c", direction: .down
    ) == "f")
    #expect(EmojiPickerGridNavigation.destinationID(
        rows: rows, currentID: "f", direction: .down
    ) == "g")
    #expect(EmojiPickerGridNavigation.destinationID(
        rows: rows, currentID: "g", direction: .up
    ) == "d")
}

@Test func emojiPickerOnlyStaysOpenForExplicitPersistentShiftSelection() {
    #expect(EmojiPickerActivationPolicy.keepsPickerPresented(
        allowsPersistentSelection: true,
        shiftPressed: true
    ))
    #expect(!EmojiPickerActivationPolicy.keepsPickerPresented(
        allowsPersistentSelection: true,
        shiftPressed: false
    ))
    #expect(!EmojiPickerActivationPolicy.keepsPickerPresented(
        allowsPersistentSelection: false,
        shiftPressed: true
    ))
}

@Test func messageActionsRemainVisibleWhileTheirReactionPickerIsPresented() {
    #expect(MessageActionVisibilityPolicy.isVisible(
        isRowHovered: true,
        isReactionPickerPresented: false,
        isEditing: false
    ))
    #expect(MessageActionVisibilityPolicy.isVisible(
        isRowHovered: false,
        isReactionPickerPresented: true,
        isEditing: false
    ))
    #expect(!MessageActionVisibilityPolicy.isVisible(
        isRowHovered: false,
        isReactionPickerPresented: false,
        isEditing: false
    ))
    #expect(!MessageActionVisibilityPolicy.isVisible(
        isRowHovered: true,
        isReactionPickerPresented: true,
        isEditing: true
    ))
}

@Test func emojiPickerOnlyAsksTheScrollViewToRevealChangedRows() {
    #expect(!EmojiPickerScrollPolicy.shouldReveal(
        previousRowID: "row:4",
        destinationRowID: "row:4"
    ))
    #expect(EmojiPickerScrollPolicy.shouldReveal(
        previousRowID: "row:4",
        destinationRowID: "row:5"
    ))
    #expect(EmojiPickerScrollPolicy.shouldReveal(
        previousRowID: nil,
        destinationRowID: "row:1"
    ))
}

@MainActor
@Test func appModelLoadsDemoAndSendsMessage() async {
    let model = AppModel(launchMode: .offlineTesting)
    await model.start()
    #expect(model.snapshot != nil)
    #expect(model.selectedChannel != nil)
    let before = model.messages.count
    model.updateDraft("hello from test")
    await model.send()
    #expect(model.messages.count == before + 1)
    #expect(model.messages.last?.content == "hello from test")
}

@Test func demoAndOfflineFlagsSelectTheSameTestingMode() {
    #expect(AppLaunchConfiguration(arguments: ["Swiftchat"]).mode == .normal)
    #expect(AppLaunchConfiguration(arguments: ["Swiftchat", "--offline"]).mode == .offlineTesting)
    #expect(AppLaunchConfiguration(arguments: ["Swiftchat", "--demo"]).mode == .offlineTesting)
    #expect(AppLaunchConfiguration(arguments: ["Swiftchat", "--demo-voice"]).mode == .offlineTesting)
    #expect(AppLaunchConfiguration(arguments: ["Swiftchat", "--demo-long-server-list"]).mode == .offlineTesting)
}

@MainActor
@Test func networkDisabledNormalLaunchStopsSignedOutWithoutMockData() async {
    let model = AppModel(launchMode: .normal, discordNetworkDisabledOverride: true)
    #expect(model.sessionState == .restoring)
    await model.start()

    #expect(model.sessionState == .signedOut)
    #expect(model.snapshot == nil)
    #expect(model.visibleChannels.isEmpty)
    #expect(!model.isOfflineTesting)
}

@MainActor
@Test func interactiveSignInKeepsLoginPresentationAliveUntilBootstrapFinishes() async {
    let provider = SuspendedBootstrapTestProvider()
    let model = AppModel(
        launchMode: .normal,
        discordNetworkDisabledOverride: false,
        restoresStoredSession: false,
        authenticatedProviderFactory: { _, _ in provider }
    )
    await model.start()
    #expect(model.sessionState == .signedOut)

    let connection = Task {
        await model.connectAuthenticatedAccount(
            CredentialHandle(accountID: "93000"),
            preservesInteractivePresentation: true
        )
    }
    await provider.waitUntilBootstrapStarts()

    // Switching to `.connecting` here destroys DiscordLoginView, whose
    // disappearance cancels the task that is performing this bootstrap.
    #expect(model.sessionState == .signedOut)

    await provider.releaseBootstrap()
    #expect(await connection.value)
    #expect(model.sessionState == .workspace)
    #expect(model.isAuthenticated)
}

@MainActor
@Test func interactiveSignInFailureStaysSignedOutAndExposesBootstrapError() async {
    let provider = SuspendedBootstrapTestProvider(bootstrapError: "fixture bootstrap stopped")
    let model = AppModel(
        launchMode: .normal,
        discordNetworkDisabledOverride: false,
        restoresStoredSession: false,
        authenticatedProviderFactory: { _, _ in provider }
    )
    await model.start()

    let connection = Task {
        await model.connectAuthenticatedAccount(
            CredentialHandle(accountID: "93000"),
            preservesInteractivePresentation: true
        )
    }
    await provider.waitUntilBootstrapStarts()
    #expect(model.sessionState == .signedOut)

    await provider.releaseBootstrap()
    #expect(!(await connection.value))
    #expect(model.sessionState == .signedOut)
    #expect(model.errorMessage == "fixture bootstrap stopped")
}

@MainActor
@Test func replyingTargetsTheSelectedMessageAndClearsAfterSending() async throws {
    let model = AppModel(launchMode: .offlineTesting)
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
    let model = AppModel(launchMode: .offlineTesting)
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
    let model = AppModel(launchMode: .offlineTesting)
    await model.start()
    let member = try #require(model.members.first)

    model.selectMember(member)
    try await Task.sleep(for: .milliseconds(20))

    let profile = try #require(model.selectedProfile)
    #expect(model.isInspectorProfilePresented)
    #expect(profile.id == member.id)
    #expect(!profile.badges.isEmpty)
    #expect(!profile.mutualGuilds.isEmpty)
    #expect(profile.status == member.status)
}

@MainActor
@Test func messageProfileDoesNotCompeteWithTheMemberInspectorPopover() async throws {
    let model = AppModel(launchMode: .offlineTesting)
    await model.start()
    let member = try #require(model.members.first)
    model.showInspector = false

    model.showProfile(for: member.user)
    try await Task.sleep(for: .milliseconds(20))

    #expect(model.selectedMember?.id == member.id)
    #expect(model.selectedProfile?.id == member.id)
    #expect(!model.isInspectorProfilePresented)
    #expect(!model.showInspector)

    model.selectMember(member)
    #expect(model.isInspectorProfilePresented)
}

@MainActor
@Test func demoEmojiPreferencesAreIsolatedAndMockEmojisDoNotUseDiscordCDN() async throws {
    let provider = MockChatProvider()
    let model = AppModel(launchMode: .offlineTesting, provider: provider)
    await model.start()

    #expect(model.favoriteEmojiKeys.isEmpty)
    #expect(model.emojiUsageCounts.isEmpty)
    model.recordEmojiUse("native:✨")
    #expect(model.emojiUsageCounts == ["native:✨": 1])

    let guildID = try #require(model.selectedGuildID)
    #expect(try await provider.emojis(in: guildID).isEmpty)
}

@MainActor
@Test func channelLoadsAreSingleFlightCachedAndProtectedFromStaleResponses() async throws {
    let provider = ChannelLoadTestProvider()
    let model = AppModel(launchMode: .offlineTesting, provider: provider)

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
    let model = AppModel(launchMode: .offlineTesting, provider: provider)
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

private actor SuspendedBootstrapTestProvider: ChatProvider {
    private let user = User(id: UserID(rawValue: 93_000), username: "tester", displayName: "Tester")
    private let channel = Channel(id: ChannelID(rawValue: 93_001), guildID: nil, name: "general")
    private var bootstrapStarted = false
    private var startWaiters: [CheckedContinuation<Void, Never>] = []
    private var bootstrapContinuation: CheckedContinuation<Void, Never>?
    private let bootstrapError: String?

    init(bootstrapError: String? = nil) {
        self.bootstrapError = bootstrapError
    }

    func bootstrap() async throws -> BootstrapSnapshot {
        bootstrapStarted = true
        startWaiters.forEach { $0.resume() }
        startWaiters.removeAll()
        await withCheckedContinuation { bootstrapContinuation = $0 }
        if let bootstrapError {
            throw ChatProviderError.invalidRequest(bootstrapError)
        }
        return BootstrapSnapshot(currentUser: user, guilds: [], channels: [channel], members: [])
    }

    func waitUntilBootstrapStarts() async {
        if bootstrapStarted { return }
        await withCheckedContinuation { startWaiters.append($0) }
    }

    func releaseBootstrap() {
        bootstrapContinuation?.resume()
        bootstrapContinuation = nil
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
    func eventStream() async -> AsyncStream<ClientEvent> { AsyncStream { $0.finish() } }
    func disconnect() async {}
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
