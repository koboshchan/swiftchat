// swift-tools-version: 6.4
import PackageDescription

let package = Package(
    name: "MediaPipeline",
    platforms: [.macOS(.v27)],
    products: [.library(name: "MediaPipeline", targets: ["MediaPipeline"])],
    dependencies: [.package(path: "../SwiftchatModels")],
    targets: [.target(name: "MediaPipeline", dependencies: ["SwiftchatModels"])]
)
