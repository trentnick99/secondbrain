// swift-tools-version:5.9
//
// SecondBrainCore — the platform-independent "organizational engine" of Coach Spark.
// Contains natural-language capture parsing, Eisenhower classification, recurrence rules,
// notification planning, and the agenda / End My Shift / weekly review builders.
//
// It depends only on Foundation so it can be unit-tested anywhere (`swift test`), including
// on Linux CI, and is linked into both the iOS app and the widget extension.

import PackageDescription

let package = Package(
    name: "SecondBrainCore",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    products: [
        .library(name: "SecondBrainCore", targets: ["SecondBrainCore"])
    ],
    targets: [
        .target(name: "SecondBrainCore"),
        .testTarget(name: "SecondBrainCoreTests", dependencies: ["SecondBrainCore"])
    ]
)
