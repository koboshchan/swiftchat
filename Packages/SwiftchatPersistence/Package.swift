// swift-tools-version: 6.4
import PackageDescription

let package = Package(
    name: "SwiftchatPersistence",
    platforms: [.macOS(.v27)],
    products: [.library(name: "SwiftchatPersistence", targets: ["SwiftchatPersistence"])],
    dependencies: [
        .package(path: "../SwiftchatModels"),
        .package(url: "https://github.com/groue/GRDB.swift.git", exact: "7.11.1"),
    ],
    targets: [
        .target(name: "SwiftchatPersistence", dependencies: ["SwiftchatModels", .product(name: "GRDB", package: "GRDB.swift")]),
        .testTarget(name: "SwiftchatPersistenceTests", dependencies: ["SwiftchatPersistence"]),
    ]
)
