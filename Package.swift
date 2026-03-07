// swift-tools-version:6.2
import PackageDescription

let package = Package(
    name: "RailMapAPI",
    platforms: [
       .macOS(.v14)
    ],
    dependencies: [
        .package(url: "https://github.com/vapor/vapor.git", from: "4.99.3"),
        .package(url: "https://github.com/apple/swift-nio.git", from: "2.65.0"),
        .package(url: "https://github.com/apple/swift-protobuf.git", .upToNextMinor(from: "1.28.1")),
        .package(path: "../LocomoSwift"),
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
            ]
        ),
        .testTarget(
            name: "AppTests",
            dependencies: [
                .target(name: "App"),
                .product(name: "XCTVapor", package: "vapor"),
            ]
        )
    ]
)
