// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ATCParserKit",
    platforms: [.iOS(.v15), .macOS(.v12)],
    products: [
        .library(name: "ATCParserKit", targets: ["ATCParserKit"]),
    ],
    targets: [
        .target(name: "ATCParserKit"),
        .testTarget(name: "ATCParserKitTests", dependencies: ["ATCParserKit"]),
    ]
)
