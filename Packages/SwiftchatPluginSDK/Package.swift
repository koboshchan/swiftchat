// swift-tools-version: 6.4
import PackageDescription

let package = Package(
    name: "SwiftchatPluginSDK",
    platforms: [.macOS(.v27)],
    products: [.library(name: "SwiftchatPluginSDK", targets: ["SwiftchatPluginSDK"])],
    targets: [
        .target(name: "SwiftchatPluginSDK"),
        .testTarget(name: "SwiftchatPluginSDKTests", dependencies: ["SwiftchatPluginSDK"])
    ]
)
