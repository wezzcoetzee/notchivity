// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Notchivity",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "NotchivityKit"),
        .executableTarget(name: "Notchivity", dependencies: ["NotchivityKit"]),
        .testTarget(name: "NotchivityKitTests", dependencies: ["NotchivityKit"]),
    ]
)
