// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Lyricise",
    platforms: [.macOS("15.0")],
    products: [
        .executable(name: "Lyricise", targets: ["Lyricise"]),
        .executable(name: "LyriciseLauncher", targets: ["LyriciseLauncher"]),
    ],
    dependencies: [
        .package(url: "https://github.com/mattt/swift-toml.git", from: "2.0.0"),
        .package(url: "https://github.com/hummingbird-project/hummingbird.git", from: "2.27.0"),
        .package(url: "https://github.com/apple/swift-http-types.git", from: "1.0.0"),
    ],
    targets: [
        .target(
            name: "LyriciseCore", dependencies: [.product(name: "TOML", package: "swift-toml")],
            resources: [.process("Resources")]),
        .target(
            name: "LyriciseBridge",
            dependencies: [
                "LyriciseCore", .product(name: "Hummingbird", package: "hummingbird"),
                .product(name: "HTTPTypes", package: "swift-http-types"),
            ]),
        .executableTarget(name: "Lyricise", dependencies: ["LyriciseCore", "LyriciseBridge"]),
        .executableTarget(name: "LyriciseLauncher"),
        .testTarget(name: "LyriciseCoreTests", dependencies: ["LyriciseCore"]),
        .testTarget(
            name: "LyriciseBridgeTests",
            dependencies: [
                "LyriciseBridge", "LyriciseCore",
                .product(name: "HummingbirdTesting", package: "hummingbird"),
                .product(name: "HTTPTypes", package: "swift-http-types"),
            ]),
    ],
    swiftLanguageModes: [.v6]
)
