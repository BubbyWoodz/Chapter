// swift-tools-version: 5.9
import PackageDescription
let package = Package(
    name: "ChapterCore", platforms: [.iOS(.v17), .macOS(.v13)],
    products: [.library(name: "ChapterCore", targets: ["ChapterCore"])],
    dependencies: [.package(url: "https://github.com/jedisct1/swift-sodium.git", revision: "cfd195c76882aa9b997560ca7cb95d72fbf5db00")],
    targets: [
        .target(name: "ChapterCore", dependencies: [.product(name: "Sodium", package: "swift-sodium")], resources: [.process("Resources")]),
        .testTarget(name: "ChapterCoreTests", dependencies: ["ChapterCore"], resources: [.process("Fixtures")])
    ]
)
