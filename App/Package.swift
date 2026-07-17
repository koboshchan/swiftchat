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
        .package(
            url: "https://github.com/llsc12/hcaptcha",
            revision: "29de12bd290c5cc9c61b3e3c15fe9a9d21449465"
        ),
    ],
    targets: [
        .executableTarget(
            name: "Swiftchat",
            dependencies: [
                "SwiftchatModels", "DiscordProtocol", "SwiftchatPersistence",
                "MessageRendering", "MediaPipeline", "SwiftchatPluginSDK",
                .product(name: "HCaptcha", package: "hcaptcha"),
            ],
            resources: [.process("Resources")],
            swiftSettings: [
                .enableUpcomingFeature("StrictConcurrency"),
                .defaultIsolation(MainActor.self),
                .interoperabilityMode(.Cxx),
            ]
        ),
        .executableTarget(name: "SwiftchatPluginHost", dependencies: ["SwiftchatPluginSDK"]),
        .testTarget(
            name: "SwiftchatAppTests",
            dependencies: ["Swiftchat", "DiscordProtocol"],
            swiftSettings: [.interoperabilityMode(.Cxx)]
        ),
    ]
)
