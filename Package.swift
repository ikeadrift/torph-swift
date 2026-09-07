// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Torph",
    platforms: [.iOS(.v17), .macOS(.v14), .tvOS(.v17), .watchOS(.v10), .visionOS(.v1)],
    products: [
        .library(name: "Torph", targets: ["Torph"])
    ],
    targets: [
        .target(name: "Torph"),
        .testTarget(name: "TorphTests", dependencies: ["Torph"], resources: [.process("Fixtures")])
    ]
)
