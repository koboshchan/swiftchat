import Foundation
import Testing
@testable import SwiftchatModels

@Test func snowflakesRoundTripAsStrings() throws {
    let id = ChannelID(rawValue: 123456789012345678)
    let data = try JSONEncoder().encode(id)
    #expect(String(decoding: data, as: UTF8.self) == "\"123456789012345678\"")
    #expect(try JSONDecoder().decode(ChannelID.self, from: data) == id)
}

@Test func legacyCachedUsersAndMembersDecodeWithCosmeticDefaults() throws {
    let userJSON = Data(#"{"id":"1","username":"legacy","displayName":"Legacy","avatarURL":null,"isBot":false}"#.utf8)
    let user = try JSONDecoder().decode(User.self, from: userJSON)
    #expect(user.publicFlags == 0)
    #expect(user.nameplate == nil)
    #expect(user.displayNameStyle == nil)

    let memberJSON = Data(#"{"user":{"id":"1","username":"legacy","displayName":"Legacy","avatarURL":null,"isBot":false},"roleName":"Member","status":"online"}"#.utf8)
    let member = try JSONDecoder().decode(Member.self, from: memberJSON)
    #expect(member.status == .online)
    #expect(member.roles.isEmpty)
    #expect(member.activityText == nil)
}

@Suite(.serialized)
struct ClientNonceTests {
    @Test func usesDiscordEpochAndDecodesToCreationTime() throws {
        let date = Date(timeIntervalSince1970: 1_784_158_980.123)
        let nonce = try #require(UInt64(ClientNonce.make(now: date)))
        let decodedMilliseconds = (nonce >> 22) + ClientNonce.discordEpochMilliseconds

        #expect(decodedMilliseconds == 1_784_158_980_123)
        #expect(nonce & 0x3F_FFFF <= 0x0FFF)
    }

    @Test func usesASequenceWithinTheSameMillisecond() throws {
        let date = Date(timeIntervalSince1970: 1_784_158_981.123)
        let first = try #require(UInt64(ClientNonce.make(now: date)))
        let second = try #require(UInt64(ClientNonce.make(now: date)))

        #expect(second == first + 1)
        #expect((first >> 22) == (second >> 22))
    }

    @Test func doesNotUnderflowBeforeDiscordEpoch() {
        let date = Date(timeIntervalSince1970: 1_000)
        #expect(ClientNonce.make(now: date) == "0")
    }
}
