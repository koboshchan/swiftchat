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
