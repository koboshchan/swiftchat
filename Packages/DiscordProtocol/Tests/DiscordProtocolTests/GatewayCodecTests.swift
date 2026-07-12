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

@Test func lossyListsKeepValidObjectsWhenDiscordAddsPartialVariants() throws {
    struct Item: Decodable, Equatable { var required: String }
    let data = Data(#"[{"required":"one"},{"new_shape":true},{"required":"two"}]"#.utf8)
    let decoded = try JSONDecoder().decode(LossyList<Item>.self, from: data)
    #expect(decoded.elements == [Item(required: "one"), Item(required: "two")])
    #expect(decoded.skippedCount == 1)
}
