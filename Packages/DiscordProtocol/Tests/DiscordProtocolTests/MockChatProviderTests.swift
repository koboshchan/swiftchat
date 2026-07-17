@testable import DiscordProtocol
import Foundation
import SwiftchatModels
import Testing

@Test func `mock fixture is synthetic rich and available offline`() async throws {
    let provider = MockChatProvider()
    let snapshot = try await provider.bootstrap()

    #expect(snapshot.currentUser.displayName == "Nova Chen")
    #expect(snapshot.guilds.count == 2)
    #expect(snapshot.guilds.allSatisfy { $0.iconURL?.isFileURL == true })
    #expect(snapshot.guilds.allSatisfy { guild in
        guild.iconURL.map { FileManager.default.fileExists(atPath: $0.path) } == true
    })

    let members = try await provider.members(in: GuildID(rawValue: 100))
    #expect(members.count == 5)
    #expect(members.allSatisfy { $0.user.avatarURL?.isFileURL == true })
    for member in members {
        let profile = try await provider.profile(for: member.user.id, in: GuildID(rawValue: 100))
        #expect(profile.bio?.isEmpty == false)
        #expect(profile.pronouns?.isEmpty == false)
        #expect(!profile.roles.isEmpty)
    }

    for rawChannelID: UInt64 in [200, 210, 211, 212, 300, 301, 302, 400] {
        let channelID = ChannelID(rawValue: rawChannelID)
        let page = try await provider.messages(in: channelID, before: nil, limit: 50)
        #expect(!page.messages.isEmpty)
    }
}

@Test func `mock long server list fixture provides scrollable guild and emoji rails`() async throws {
    let provider = MockChatProvider(includesLongServerList: true)
    let snapshot = try await provider.bootstrap()

    #expect(snapshot.guilds.count == 20)
    let lastGuild = try #require(snapshot.guilds.last)
    #expect(lastGuild.name == "Scroll Test 18")
    #expect(lastGuild.iconURL == nil)

    let channels = try await provider.channels(in: lastGuild.id)
    let channel = try #require(channels.first)
    #expect(channel.name == "general")
    #expect(try await !(provider.messages(in: channel.id, before: nil, limit: 50)).messages.isEmpty)
    #expect(try await (provider.members(in: lastGuild.id)).count == 2)
}

@Test func `mock attachment send copies the selected file into demo storage`() async throws {
    let provider = MockChatProvider()
    _ = try await provider.bootstrap()
    let sourceDirectory = FileManager.default.temporaryDirectory
        .appending(path: UUID().uuidString, directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: sourceDirectory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: sourceDirectory) }
    let source = sourceDirectory.appending(path: "demo-note.txt")
    let contents = Data("A fictional attachment from the SwiftChat demo.".utf8)
    try contents.write(to: source)

    let sent = try await provider.send(SendMessageDraft(
        channelID: ChannelID(rawValue: 210),
        content: "",
        attachmentURLs: [source],
        nonce: "demo-attachment-test"
    ))
    let attachment = try #require(sent.attachments.first)
    defer { try? FileManager.default.removeItem(at: attachment.url) }

    #expect(attachment.filename == "demo-note.txt")
    #expect(attachment.mediaType == "text/plain")
    #expect(attachment.size == contents.count)
    #expect(attachment.url != source)
    #expect(attachment.url.isFileURL)
    #expect(try Data(contentsOf: attachment.url) == contents)
}
