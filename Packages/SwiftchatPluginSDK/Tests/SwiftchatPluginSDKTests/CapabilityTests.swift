import Testing
@testable import SwiftchatPluginSDK

@Test func mutatingCapabilitiesAreSensitive() {
    #expect(PluginCapability.sendMessages.isSensitive)
    #expect(!PluginCapability.addCommands.isSensitive)
}

