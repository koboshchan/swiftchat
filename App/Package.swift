// swift-tools-version: 6.4
import PackageDescription

let package = Package(
    name: "SwiftchatApp",
    platforms: [.macOS(.v27)],
    products: [
        .executable(name: "Swiftchat", targets: ["Swiftchat"]),
        .executable(name: "SwiftchatPluginHost", targets: ["SwiftchatPluginHost"]),
    ],
    dependencies: [
        .package(path: "../Packages/SwiftchatModels"),
        .package(path: "../Packages/DiscordProtocol"),
        .package(path: "../Packages/SwiftchatPersistence"),
        .package(path: "../Packages/MessageRendering"),
        .package(path: "../Packages/MediaPipeline"),
        .package(path: "../Packages/SwiftchatPluginSDK"),
    ],
    targets: [
        .executableTarget(
            name: "Swiftchat",
            dependencies: [
                "SwiftchatModels", "DiscordProtocol", "SwiftchatPersistence",
                "MessageRendering", "MediaPipeline", "SwiftchatPluginSDK",
            ],
            swiftSettings: [
                .enableUpcomingFeature("StrictConcurrency"),
                .defaultIsolation(MainActor.self),
            ]
        ),
        .executableTarget(name: "SwiftchatPluginHost", dependencies: ["SwiftchatPluginSDK"]),
        .testTarget(name: "SwiftchatAppTests", dependencies: ["Swiftchat", "DiscordProtocol"]),
    ]
)
