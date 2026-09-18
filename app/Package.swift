// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "Squawk",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "SquawkCore"),
        .executableTarget(
            name: "Squawk",
            dependencies: ["SquawkCore"]
        ),
        // Named for the file it builds, not the command it becomes. macOS
        // filesystems are case insensitive, so a target named "squawk" would
        // collide with the app target in one build directory.
        .executableTarget(
            name: "squawk-hook",
            dependencies: ["SquawkCore"]
        ),
        .testTarget(
            name: "SquawkCoreTests",
            dependencies: ["SquawkCore"]
        ),
    ]
)
