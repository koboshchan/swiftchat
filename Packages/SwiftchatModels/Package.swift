// swift-tools-version: 6.4
import PackageDescription

let package = Package(
    name: "SwiftchatModels",
    platforms: [.macOS(.v27)],
    products: [.library(name: "SwiftchatModels", targets: ["SwiftchatModels"])],
    targets: [
        .target(name: "SwiftchatModels"),
        .testTarget(name: "SwiftchatModelsTests", dependencies: ["SwiftchatModels"])
    ]
)
