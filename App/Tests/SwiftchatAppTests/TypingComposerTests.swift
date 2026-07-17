import DiscordProtocol
import Foundation
@testable import Swiftchat
import SwiftchatModels
import Testing

@MainActor
@Test func `typing state supports multiple users independent refresh and self suppression`() {
    let state = TypingStateModel(expiry: .milliseconds(40))
    let channel = ChannelID(rawValue: 10)
    let current = User(id: UserID(rawValue: 1), username: "me", displayName: "Me")
    let amy = User(id: UserID(rawValue: 2), username: "amy", displayName: "Amy")
    let ben = User(id: UserID(rawValue: 3), username: "ben", displayName: "Ben")
    let cy = User(id: UserID(rawValue: 4), username: "cy", displayName: "Cy")

    state.receive(channelID: channel, user: current, currentUserID: current.id)
    #expect(state.presentation(in: channel) == nil)
    state.receive(channelID: channel, user: amy, currentUserID: current.id)
    #expect(state.presentation(in: channel) == "Amy is typing…")
    state.receive(channelID: channel, user: ben, currentUserID: current.id)
    #expect(state.presentation(in: channel) == "Amy and Ben are typing…")
    state.receive(channelID: channel, user: cy, currentUserID: current.id)
    #expect(state.presentation(in: channel) == "Amy, Ben, and 1 other are typing…")

    state.clear(userID: ben.id, in: channel)
    #expect(state.presentation(in: channel) == "Amy and Cy are typing…")
    let amyGeneration = state.expiryGenerationForTesting(channelID: channel, userID: amy.id)
    let oldCyGeneration = state.expiryGenerationForTesting(channelID: channel, userID: cy.id)
    state.receive(channelID: channel, user: cy, currentUserID: current.id)
    let refreshedCyGeneration = state.expiryGenerationForTesting(channelID: channel, userID: cy.id)
    state.applyExpiryForTesting(channelID: channel, userID: amy.id, generation: amyGeneration ?? 0)
    #expect(state.presentation(in: channel) == "Cy is typing…")
    state.applyExpiryForTesting(channelID: channel, userID: cy.id, generation: oldCyGeneration ?? 0)
    #expect(state.presentation(in: channel) == "Cy is typing…")
    state.applyExpiryForTesting(channelID: channel, userID: cy.id, generation: refreshedCyGeneration ?? 0)
    #expect(state.presentation(in: channel) == nil)
}

@MainActor
@Test func `typing state expires automatically`() async {
    let state = TypingStateModel(expiry: .milliseconds(10))
    let channel = ChannelID(rawValue: 20)
    let user = User(id: UserID(rawValue: 21), username: "timer", displayName: "Timer")
    state.receive(channelID: channel, user: user, currentUserID: nil)
    #expect(state.presentation(in: channel) != nil)
    try? await Task.sleep(for: .milliseconds(30))
    #expect(await eventuallyOnMain { state.presentation(in: channel) == nil })
}

@MainActor
@Test func `remote typing is channel scoped cleared by message and disconnect`() async throws {
    let provider = TypingTestProvider()
    let model = AppModel(launchMode: .offlineTesting, provider: provider, typingExpiry: .seconds(1))
    await model.start()
    let text = try #require(model.selectedChannel)
    let other = provider.otherUser
    let third = User(id: UserID(rawValue: 3), username: "third", displayName: "Third")

    await provider.emit(.typing(channelID: text.id, user: other))
    await provider.emit(.typing(channelID: ChannelID(rawValue: 12), user: third))
    #expect(await eventuallyOnMain { model.typingState.presentation(in: text.id) == "Other is typing…" })
    #expect(await eventuallyOnMain {
        model.typingState.presentation(in: ChannelID(rawValue: 12)) == "Third is typing…"
    })

    await provider.emit(.messageCreated(Message(
        id: MessageID(rawValue: 99),
        channelID: text.id,
        author: other,
        content: "sent"
    )))
    #expect(await eventuallyOnMain { model.typingState.presentation(in: text.id) == nil })

    await provider.emit(.connectionChanged(.disconnected))
    #expect(await eventuallyOnMain { model.typingState.presentation(in: ChannelID(rawValue: 12)) == nil })
}

@MainActor
@Test func `local typing debounces throttles and cancels for draft send and channel changes`() async throws {
    let provider = TypingTestProvider()
    let model = AppModel(
        launchMode: .offlineTesting,
        provider: provider,
        localTypingTiming: .init(debounce: .milliseconds(10), throttle: .milliseconds(50))
    )
    await model.start()
    let textID = try #require(model.selectedChannelID)

    // Loading/restoring a draft is not a user edit and must not emit typing.
    try? await Task.sleep(for: .milliseconds(20))
    #expect(await provider.typingCount == 0)

    model.updateDraft("h")
    model.updateDraft("he")
    model.updateDraft("hello")
    try? await Task.sleep(for: .milliseconds(25))
    #expect(await provider.typingCount == 1)
    #expect(await provider.typingChannels == [textID])

    model.updateDraft("hello!")
    model.updateDraft("hello!!")
    try? await Task.sleep(for: .milliseconds(15))
    #expect(await provider.typingCount == 1)
    try? await Task.sleep(for: .milliseconds(50))
    #expect(await provider.typingCount == 2)

    model.updateDraft("pending")
    model.updateDraft("")
    try? await Task.sleep(for: .milliseconds(20))
    #expect(await provider.typingCount == 2)

    model.updateDraft("send now")
    await model.send()
    try? await Task.sleep(for: .milliseconds(20))
    #expect(await provider.typingCount == 2)

    model.selectedChannelID = ChannelID(rawValue: 11)
    model.updateDraft("voice draft")
    try? await Task.sleep(for: .milliseconds(20))
    #expect(await provider.typingCount == 2)

    model.selectedChannelID = ChannelID(rawValue: 12)
    model.updateDraft("other channel")
    model.selectedChannelID = textID
    try? await Task.sleep(for: .milliseconds(20))
    #expect(await provider.typingCount == 2)
}

@MainActor
@Test func `mock typing is deterministic and rejects voice channels`() async throws {
    let provider = MockChatProvider()
    _ = try await provider.bootstrap()
    try await provider.sendTyping(in: ChannelID(rawValue: 210))
    try await provider.sendTyping(in: ChannelID(rawValue: 210))
    #expect(await provider.typingRequests == [ChannelID(rawValue: 210), ChannelID(rawValue: 210)])
    await #expect(throws: ChatProviderError.self) {
        try await provider.sendTyping(in: ChannelID(rawValue: 230))
    }
}

@MainActor
@Test func `composer return decision covers setting shift command and IME`() {
    #expect(ComposerReturnAction.decide(
        sendWithReturn: true, shift: false, command: false, hasMarkedText: false
    ) == .send)
    #expect(ComposerReturnAction.decide(
        sendWithReturn: true, shift: true, command: false, hasMarkedText: false
    ) == .newline)
    #expect(ComposerReturnAction.decide(
        sendWithReturn: false, shift: false, command: false, hasMarkedText: false
    ) == .newline)
    #expect(ComposerReturnAction.decide(
        sendWithReturn: false, shift: false, command: true, hasMarkedText: false
    ) == .send)
    #expect(ComposerReturnAction.decide(
        sendWithReturn: true, shift: false, command: false, hasMarkedText: true
    ) == .inputMethod)
}

@MainActor
@Test func `attachment only send works and whitespace only does not send`() async {
    let provider = TypingTestProvider()
    let model = AppModel(launchMode: .offlineTesting, provider: provider)
    await model.start()
    let before = await provider.sendCount
    model.updateDraft("  \n")
    await model.send()
    #expect(await provider.sendCount == before)

    let attachment = URL(fileURLWithPath: "/tmp/swiftchat-test-attachment")
    await model.send(attachments: [attachment])
    #expect(await provider.sendCount == before + 1)
}

@MainActor
private func eventuallyOnMain(_ condition: @escaping @MainActor () -> Bool) async -> Bool {
    for _ in 0 ..< 200 {
        if condition() {
            return true
        }
        try? await Task.sleep(for: .milliseconds(1))
    }
    return condition()
}

private actor TypingTestProvider: ChatProvider {
    let currentUser = User(id: UserID(rawValue: 1), username: "me", displayName: "Me")
    let otherUser = User(id: UserID(rawValue: 2), username: "other", displayName: "Other")
    private let channels = [
        Channel(id: ChannelID(rawValue: 10), guildID: nil, name: "text", kind: .directMessage),
        Channel(id: ChannelID(rawValue: 11), guildID: nil, name: "voice", kind: .voice),
        Channel(id: ChannelID(rawValue: 12), guildID: nil, name: "group", kind: .groupDirectMessage)
    ]
    private var continuation: AsyncStream<ClientEvent>.Continuation?
    private(set) var typingChannels: [ChannelID] = []
    private(set) var sendCount = 0
    private var nextMessageID: UInt64 = 100

    var typingCount: Int {
        typingChannels.count
    }

    func bootstrap() async throws -> BootstrapSnapshot {
        continuation?.yield(.connectionChanged(.ready))
        return BootstrapSnapshot(currentUser: currentUser, guilds: [], channels: channels, members: [])
    }

    func channels(in guildID: GuildID?) async throws -> [Channel] {
        channels
    }

    func members(in guildID: GuildID?) async throws -> [Member] {
        []
    }

    func profile(for userID: UserID, in guildID: GuildID?) async throws -> UserProfile {
        throw ChatProviderError.invalidRequest("not used")
    }

    func currentStatus() async -> PresenceStatus {
        .online
    }

    func updateStatus(_ status: PresenceStatus) async throws {}
    func messages(in channelID: ChannelID, before: MessageID?, limit: Int) async throws -> MessagePage {
        MessagePage(messages: [], hasMoreBefore: false)
    }

    func sendTyping(in channelID: ChannelID) async throws {
        typingChannels.append(channelID)
    }

    func send(_ draft: SendMessageDraft) async throws -> Message {
        sendCount += 1
        nextMessageID += 1
        let message = Message(
            id: MessageID(rawValue: nextMessageID),
            channelID: draft.channelID,
            author: currentUser,
            content: draft.content,
            attachments: draft.attachmentURLs.enumerated().map {
                Attachment(id: "\(nextMessageID)-\($0.offset)", filename: $0.element.lastPathComponent, url: $0.element)
            },
            nonce: draft.nonce
        )
        continuation?.yield(.messageCreated(message))
        return message
    }

    func edit(messageID: MessageID, channelID: ChannelID, content: String) async throws -> Message {
        throw ChatProviderError.invalidRequest("not used")
    }

    func delete(messageID: MessageID, channelID: ChannelID) async throws {}
    func toggleReaction(_ emoji: String, messageID: MessageID, channelID: ChannelID) async throws {}
    func eventStream() async -> AsyncStream<ClientEvent> {
        let stream = AsyncStream<ClientEvent>.makeStream(bufferingPolicy: .bufferingNewest(50))
        continuation = stream.continuation
        return stream.stream
    }

    func disconnect() async {
        continuation?.yield(.connectionChanged(.disconnected))
    }

    func emit(_ event: ClientEvent) {
        continuation?.yield(event)
    }
}
