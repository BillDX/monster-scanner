// swift-tools-version: 6.0
// MonsterCore holds the deterministic game logic ("the code decides"):
// monsters, clues, the verdict engine, moon phase, JSON parsing and templates.
// It has no UI and no third-party dependencies, so it can be tested quickly
// on the Mac with `swift test` as well as inside Xcode.

import PackageDescription

let package = Package(
    name: "MonsterCore",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
    ],
    products: [
        .library(name: "MonsterCore", targets: ["MonsterCore"]),
    ],
    targets: [
        .target(name: "MonsterCore"),
        .testTarget(name: "MonsterCoreTests", dependencies: ["MonsterCore"]),
    ]
)
