// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "RailMapAPI",
    platforms: [
       .macOS(.v13)
    ],
    dependencies: [
        // 💧 A server-side Swift web framework.
        .package(url: "https://github.com/vapor/vapor.git", from: "4.99.3"),
        // 🔵 Non-blocking, event-driven networking for Swift. Used for custom executors
        .package(url: "https://github.com/apple/swift-nio.git", from: "2.65.0"),
        .package(url: "https://github.com/apple/swift-protobuf.git", .upToNextMinor(from: "1.28.1")),
        .package(path: "../LocomoSwift"),
//        .package(url: "https://github.com/RailMapiOS/LocomoSwift.git", .upToNextMinor(from: "0.0.7")),
        .package(url: "https://github.com/weichsel/ZIPFoundation.git", .upToNextMinor(from: "0.9.19")),
        .package(url: "https://github.com/vapor/fluent-sqlite-driver.git", .upToNextMinor(from: "4.8.0")),
        .package(url: "https://github.com/vapor/fluent.git", .upToNextMinor(from: "4.12.0"))
    ],
    targets: [
        .executableTarget(
            name: "App",
            dependencies: [
                .product(name: "Vapor", package: "vapor"),
                .product(name: "NIOCore", package: "swift-nio"),
                .product(name: "NIOPosix", package: "swift-nio"),
                .product(name: "SwiftProtobuf", package: "swift-protobuf"),
                .product(name: "LocomoSwift", package: "LocomoSwift"),
                .product(name: "ZIPFoundation", package: "ZIPFoundation"),
                .product(name: "FluentSQLiteDriver", package: "fluent-sqlite-driver"),
                .product(name: "Fluent", package: "fluent"),
            ],
            swiftSettings: swiftSettings
        ),
        .testTarget(
            name: "AppTests",
            dependencies: [
                .target(name: "App"),
                .product(name: "XCTVapor", package: "vapor"),
            ],
            swiftSettings: swiftSettings
        )
    ]
)

var swiftSettings: [SwiftSetting] { [
    .enableUpcomingFeature("DisableOutwardActorInference"),
    .enableExperimentalFeature("StrictConcurrency"),
] }
