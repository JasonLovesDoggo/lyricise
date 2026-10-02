// swift-tools-version: 6.2
import PackageDescription
let package = Package(
    name: "Lyricise",
    platforms: [.macOS("27.0")],
    products: [.library(name: "LyriciseCore", targets: ["LyriciseCore"])],
    dependencies: [.package(url: "https://github.com/mattt/swift-toml.git", from: "2.0.0")],
    targets: [
        .target(name: "LyriciseCore", dependencies: [.product(name: "TOML", package: "swift-toml")])
    ],
    swiftLanguageModes: [.v6]
)
