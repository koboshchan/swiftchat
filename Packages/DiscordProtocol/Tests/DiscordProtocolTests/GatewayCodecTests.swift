import SwiftchatModels
import Foundation
import Testing
@testable import DiscordProtocol

@Test func jsonGatewayCodecRoundTripsUnknownEvents() throws {
    let codec = JSONGatewayCodec()
    let envelope = GatewayEnvelope(op: 0, data: .object(["future": .bool(true)]), sequence: 42, eventName: "FUTURE_EVENT")
    #expect(try codec.decode(codec.encode(envelope)) == envelope)
}

@Test func productionBaselineMatchesObservedBootstrap() {
    let baseline = DiscordProductionBaseline.july2026
    #expect(baseline.apiVersion == 9)
    #expect(baseline.desktopGatewayEncoding == "etf")
    #expect(baseline.desktopGatewayCompression == "zstd-stream")
    #expect(baseline.defaultCapabilities == 1_734_653)
}

@Test func settingsProtoPreservesDiscordGuildFolderOrder() {
    func fixed64(_ value: UInt64) -> [UInt8] {
        (0..<8).map { UInt8(truncatingIfNeeded: value >> UInt64($0 * 8)) }
    }
    func folder(_ ids: [UInt64]) -> [UInt8] {
        let packed = ids.flatMap(fixed64)
        return [0x0a, UInt8(packed.count)] + packed
    }
    let firstFolder = folder([300, 100])
    let standalone = folder([200])
    let guildFolders = [0x0a, UInt8(firstFolder.count)] + firstFolder
        + [0x0a, UInt8(standalone.count)] + standalone
    let topLevel = Data([0x72, UInt8(guildFolders.count)] + guildFolders)

    #expect(DiscordSettingsProto.guildOrder(from: topLevel) == [
        GuildID(rawValue: 300), GuildID(rawValue: 100), GuildID(rawValue: 200),
    ])
}

@Test func settingsProtoKeepsFolderOrderWhenPositionsContainAnUnlistedGuild() {
    func fixed64(_ value: UInt64) -> [UInt8] {
        (0..<8).map { UInt8(truncatingIfNeeded: value >> UInt64($0 * 8)) }
    }
    func folder(_ ids: [UInt64]) -> [UInt8] {
        let packed = ids.flatMap(fixed64)
        return [0x0a, UInt8(packed.count)] + packed
    }

    let folderPayload = folder([300, 100, 200])
    let completePositions = [400, 300, 100, 200].flatMap(fixed64)
    let guildFolders = [0x0a, UInt8(folderPayload.count)] + folderPayload
        + [0x12, UInt8(completePositions.count)] + completePositions
    let topLevel = Data([0x72, UInt8(guildFolders.count)] + guildFolders)

    #expect(DiscordSettingsProto.guildOrder(from: topLevel) == [
        GuildID(rawValue: 300), GuildID(rawValue: 100), GuildID(rawValue: 200),
    ])
}

@Test func guildsMissingFromSettingsAppearAboveTheStoredSequence() {
    let stored = Guild(id: GuildID(rawValue: 100), name: "Stored")
    let newlyCreated = Guild(id: GuildID(rawValue: 400), name: "Testing Server 2")
    let olderUnlisted = Guild(id: GuildID(rawValue: 300), name: "Older unlisted")

    #expect(DiscordRESTProvider.applyingGuildOrder(
        [stored.id], to: [stored, olderUnlisted, newlyCreated]
    ).map(\.id) == [
        newlyCreated.id, olderUnlisted.id, stored.id,
    ])
}

@Test func guildMemberSubscriptionMatchesCurrentDiscordBulkShape() throws {
    let payload = DiscordGatewayPayloadFactory.guildSubscriptions(
        guildID: GuildID(rawValue: 100),
        channelID: ChannelID(rawValue: 200)
    )
    #expect(payload["op"] as? Int == 37)
    let data = try #require(payload["d"] as? [String: Any])
    let subscriptions = try #require(data["subscriptions"] as? [String: Any])
    let guild = try #require(subscriptions["100"] as? [String: Any])
    #expect(guild["typing"] as? Bool == true)
    #expect(guild["activities"] as? Bool == true)
    #expect(guild["threads"] as? Bool == true)
    let channels = try #require(guild["channels"] as? [String: Any])
    #expect(channels["200"] as? [[Int]] == [[0, 99]])
}

@Test func voiceStateUpdateUsesGatewayOpcodeFourAndExplicitNullToLeave() throws {
    let join = DiscordGatewayPayloadFactory.voiceStateUpdate(
        guildID: GuildID(rawValue: 100),
        channelID: ChannelID(rawValue: 230),
        selfMute: true,
        selfDeaf: false
    )
    #expect(join["op"] as? Int == 4)
    let joinData = try #require(join["d"] as? [String: Any])
    #expect(joinData["guild_id"] as? String == "100")
    #expect(joinData["channel_id"] as? String == "230")
    #expect(joinData["self_mute"] as? Bool == true)
    #expect(joinData["self_video"] as? Bool == false)
    #expect(joinData["self_stream"] as? Bool == false)

    let camera = DiscordGatewayPayloadFactory.voiceStateUpdate(
        guildID: GuildID(rawValue: 100),
        channelID: ChannelID(rawValue: 230),
        selfMute: false,
        selfDeaf: false,
        selfVideo: true
    )
    let cameraData = try #require(camera["d"] as? [String: Any])
    #expect(cameraData["self_video"] as? Bool == true)

    let leave = DiscordGatewayPayloadFactory.voiceStateUpdate(
        guildID: GuildID(rawValue: 100),
        channelID: nil,
        selfMute: false,
        selfDeaf: false
    )
    let leaveData = try #require(leave["d"] as? [String: Any])
    #expect(leaveData["channel_id"] is NSNull)
}

@Test func voiceServerMigrationWaitsForAllocationThenReconnects() throws {
    let active = VoiceConnectionInfo(
        serverID: "100",
        channelID: ChannelID(rawValue: 230),
        guildID: GuildID(rawValue: 100),
        userID: UserID(rawValue: 300),
        sessionID: "session",
        token: "old-token",
        endpoint: "old.discord.media"
    )
    let deallocation = try JSONDecoder().decode(
        VoiceServerUpdateDTO.self,
        from: Data(#"{"token":"new-token","guild_id":"100","endpoint":null}"#.utf8)
    )
    #expect(
        VoiceServerMigrationResolver.resolve(update: deallocation, activeConnection: active)
            == .waitForAllocation
    )

    let allocation = try JSONDecoder().decode(
        VoiceServerUpdateDTO.self,
        from: Data(#"{"token":"new-token","guild_id":"100","endpoint":"new.discord.media"}"#.utf8)
    )
    var expected = active
    expected.token = "new-token"
    expected.endpoint = "new.discord.media"
    #expect(
        VoiceServerMigrationResolver.resolve(update: allocation, activeConnection: active)
            == .reconnect(expected)
    )

    let duplicate = try JSONDecoder().decode(
        VoiceServerUpdateDTO.self,
        from: Data(#"{"token":"old-token","guild_id":"100","endpoint":"old.discord.media"}"#.utf8)
    )
    #expect(VoiceServerMigrationResolver.resolve(update: duplicate, activeConnection: active) == nil)

    let otherGuild = try JSONDecoder().decode(
        VoiceServerUpdateDTO.self,
        from: Data(#"{"token":"other","guild_id":"999","endpoint":"other.discord.media"}"#.utf8)
    )
    #expect(VoiceServerMigrationResolver.resolve(update: otherGuild, activeConnection: active) == nil)
}

@Test func guildCreateSnapshotSeedsExistingVoiceParticipants() throws {
    let data = Data(#"""
    {
        "id":"100",
        "voice_states":[
            {"user_id":"200","channel_id":"300","session_id":"existing","self_mute":false,"self_deaf":false,"self_video":true},
            {"future_shape":true}
        ]
    }
    """#.utf8)
    let snapshot = try JSONDecoder().decode(GuildVoiceStateSnapshotDTO.self, from: data)
    let state = try #require(snapshot.domainVoiceStates.first)

    #expect(snapshot.domainVoiceStates.count == 1)
    #expect(state.userID == UserID(rawValue: 200))
    #expect(state.guildID == GuildID(rawValue: 100))
    #expect(state.channelID == ChannelID(rawValue: 300))
    #expect(state.isVideoEnabled)
}

@Test func readySupplementalSeedsVoiceParticipantsUsingReadyGuildOrder() throws {
    let data = Data(#"""
    {
        "merged_voice_states": {
            "guilds": [
                [{"user_id":"200","channel_id":"300","session_id":"existing","self_mute":false,"self_deaf":false}],
                [{"user_id":"201","channel_id":"301","guild_id":"101","session_id":"other","self_video":true}]
            ]
        }
    }
    """#.utf8)
    let states = ReadySupplementalVoiceStateResolver.resolve(
        data: data,
        gatewayGuildIDs: [GuildID(rawValue: 100), GuildID(rawValue: 999)]
    )

    #expect(states.first(where: { $0.userID == UserID(rawValue: 200) })?.guildID == GuildID(rawValue: 100))
    #expect(states.first(where: { $0.userID == UserID(rawValue: 201) })?.guildID == GuildID(rawValue: 101))
    #expect(states.first(where: { $0.userID == UserID(rawValue: 201) })?.isVideoEnabled == true)
}

@Test func readySupplementalSkipsNullGuildBatchesAndFutureVoiceStates() throws {
    let data = Data(#"""
    {
        "merged_voice_states": {
            "guilds": [
                null,
                [null,{"future_shape":true},{"user_id":"202","channel_id":"302","session_id":"valid"}]
            ]
        }
    }
    """#.utf8)
    let states = ReadySupplementalVoiceStateResolver.resolve(
        data: data,
        gatewayGuildIDs: [GuildID(rawValue: 100), GuildID(rawValue: 101)]
    )

    #expect(states.count == 1)
    #expect(states.first?.guildID == GuildID(rawValue: 101))
    #expect(states.first?.channelID == ChannelID(rawValue: 302))
}

@Test func readyPayloadCanSeedEmbeddedVoiceParticipants() throws {
    let data = Data(#"""
    {
        "guilds": [
            {
                "id":"100",
                "voice_states":[
                    {"user_id":"200","channel_id":"300","session_id":"existing"},
                    {"future_shape":true}
                ]
            }
        ]
    }
    """#.utf8)
    let ready = try JSONDecoder().decode(GatewayReadyGuildsDTO.self, from: data)
    let guild = try #require(ready.guilds.first)
    let participant = try #require(guild.voiceStates.first?.domain(defaultGuildID: GuildID(guild.id)))

    #expect(guild.voiceStates.count == 1)
    #expect(participant.guildID == GuildID(rawValue: 100))
    #expect(participant.channelID == ChannelID(rawValue: 300))
}

@Test func lossyListsKeepValidObjectsWhenDiscordAddsPartialVariants() throws {
    struct Item: Decodable, Equatable { var required: String }
    let data = Data(#"[{"required":"one"},{"new_shape":true},{"required":"two"}]"#.utf8)
    let decoded = try JSONDecoder().decode(LossyList<Item>.self, from: data)
    #expect(decoded.elements == [Item(required: "one"), Item(required: "two")])
    #expect(decoded.skippedCount == 1)
}
