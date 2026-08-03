// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ATCParserKit",
    platforms: [.iOS(.v15), .macOS(.v12)],
    products: [
        .library(name: "ATCParserKit", targets: ["ATCParserKit"]),
        .library(name: "ATCParserFFI", targets: ["ATCParserFFI"]),
    ],
    targets: [
        .target(name: "ATCParserKit"),
        .target(name: "ATCParserFFI", dependencies: ["ATCParserKit"]),
        .testTarget(name: "ATCParserKitTests",
                    dependencies: ["ATCParserKit"],
                    resources: [.copy("Fixtures")]),
    ]
)
