import Foundation
@testable import SwiftchatModels
import Testing

@Test func `snowflakes round trip as strings`() throws {
    let id = ChannelID(rawValue: 123_456_789_012_345_678)
    let data = try JSONEncoder().encode(id)
    #expect(String(decoding: data, as: UTF8.self) == "\"123456789012345678\"")
    #expect(try JSONDecoder().decode(ChannelID.self, from: data) == id)
}

@Test func `legacy cached users and members decode with cosmetic defaults`() throws {
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
    @Test func `uses discord epoch and decodes to creation time`() throws {
        let date = Date(timeIntervalSince1970: 1_784_158_980.123)
        let nonce = try #require(UInt64(ClientNonce.make(now: date)))
        let decodedMilliseconds = (nonce >> 22) + ClientNonce.discordEpochMilliseconds

        #expect(decodedMilliseconds == 1_784_158_980_123)
        #expect(nonce & 0x3FFFFF <= 0x0FFF)
    }

    @Test func `uses A sequence within the same millisecond`() throws {
        let date = Date(timeIntervalSince1970: 1_784_158_981.123)
        let first = try #require(UInt64(ClientNonce.make(now: date)))
        let second = try #require(UInt64(ClientNonce.make(now: date)))

        #expect(second == first + 1)
        #expect((first >> 22) == (second >> 22))
    }

    @Test func `does not underflow before discord epoch`() {
        let date = Date(timeIntervalSince1970: 1000)
        #expect(ClientNonce.make(now: date) == "0")
    }
}
