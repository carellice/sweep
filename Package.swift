// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "Sweep",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "SweepCore"),
        .executableTarget(name: "Sweep", dependencies: ["SweepCore"]),
        .testTarget(name: "SweepCoreTests", dependencies: ["SweepCore"]),
    ]
)
