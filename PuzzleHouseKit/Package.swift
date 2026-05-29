// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PuzzleHouseKit",
    platforms: [
        .iOS("26.0"),
        .macOS("26.0"),
    ],
    products: [
        .library(name: "PuzzleCore", targets: ["PuzzleCore"]),
        .library(name: "PuzzleParsers", targets: ["PuzzleParsers"]),
        .library(name: "PuzzleScoring", targets: ["PuzzleScoring"]),
        .library(name: "PuzzleCloudKit", targets: ["PuzzleCloudKit"]),
        .library(name: "PuzzleVision", targets: ["PuzzleVision"]),
        .library(name: "PuzzleUI", targets: ["PuzzleUI"]),
        .library(name: "PuzzleHouseApp", targets: ["PuzzleHouseApp"]),
        .library(name: "PuzzleShareKit", targets: ["PuzzleShareKit"]),
        .executable(name: "puzzlecheck", targets: ["puzzlecheck"]),
        .executable(name: "make-icon", targets: ["make-icon"]),
    ],
    targets: [
        .target(name: "PuzzleCore"),
        .target(name: "PuzzleParsers", dependencies: ["PuzzleCore"]),
        .target(name: "PuzzleScoring", dependencies: ["PuzzleCore"]),
        .target(name: "PuzzleCloudKit", dependencies: ["PuzzleCore"]),
        .target(name: "PuzzleVision", dependencies: ["PuzzleCore", "PuzzleParsers"]),
        .target(name: "PuzzleUI", dependencies: ["PuzzleCore", "PuzzleScoring"]),
        .target(
            name: "PuzzleHouseApp",
            dependencies: [
                "PuzzleCore", "PuzzleParsers", "PuzzleScoring",
                "PuzzleCloudKit", "PuzzleUI", "PuzzleVision",
            ]
        ),
        .target(
            name: "PuzzleShareKit",
            dependencies: ["PuzzleCore", "PuzzleParsers", "PuzzleCloudKit"]
        ),
        .executableTarget(
            name: "puzzlecheck",
            dependencies: ["PuzzleParsers", "PuzzleCore"]
        ),
        .executableTarget(name: "make-icon"),

        .testTarget(name: "PuzzleCoreTests", dependencies: ["PuzzleCore"]),
        .testTarget(name: "PuzzleParsersTests", dependencies: ["PuzzleParsers", "PuzzleCore", "PuzzleVision"]),
        .testTarget(name: "PuzzleScoringTests", dependencies: ["PuzzleScoring", "PuzzleCore"]),
        .testTarget(
            name: "PuzzleCloudKitTests",
            dependencies: ["PuzzleCloudKit", "PuzzleCore"]
        ),
        .testTarget(
            name: "PuzzleHouseAppTests",
            dependencies: ["PuzzleHouseApp", "PuzzleCore", "PuzzleCloudKit"]
        ),
    ]
)
