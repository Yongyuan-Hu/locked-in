// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "LockedIn",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "LockedInCore", targets: ["LockedInCore"]),
        .executable(name: "LockedIn", targets: ["LockedIn"])
    ],
    targets: [
        .target(name: "LockedInCore"),
        .executableTarget(name: "LockedIn", dependencies: ["LockedInCore"]),
        .executableTarget(name: "CoreChecks", dependencies: ["LockedInCore"], path: "Tests/CoreChecks"),
        .testTarget(name: "LockedInCoreTests", dependencies: ["LockedInCore"])
    ]
)
