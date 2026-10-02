// swift-tools-version: 6.2
import PackageDescription
let package = Package(
    name: "Lyricise",
    platforms: [.macOS("27.0")],
    products: [.executable(name: "Lyricise", targets: ["Lyricise"]), .executable(name: "LyriciseLauncher", targets: ["LyriciseLauncher"])],
    dependencies: [.package(url: "https://github.com/mattt/swift-toml.git", from: "2.0.0")],
    targets: [
        .target(name: "LyriciseCore", dependencies: [.product(name: "TOML", package: "swift-toml")]),
        .executableTarget(name: "Lyricise", dependencies: ["LyriciseCore"]),
        .executableTarget(name: "LyriciseLauncher"),
        .testTarget(name: "LyriciseCoreTests", dependencies: ["LyriciseCore"])
    ],
    swiftLanguageModes: [.v6]
)
