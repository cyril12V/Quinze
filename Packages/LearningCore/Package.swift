// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "LearningCore",
    defaultLocalization: "fr",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        // Tiny, dependency-free types shared with the Screen Time extensions (memory-constrained).
        .library(name: "LearningPrimitives", targets: ["LearningPrimitives"]),
        // The pedagogical engine: content model, FSRS scheduling, answer evaluation,
        // session planning, mastery, diagnostic. Foundation only, UI-independent.
        .library(name: "LearningCore", targets: ["LearningCore"]),
    ],
    targets: [
        .target(name: "LearningPrimitives"),
        .target(name: "LearningCore", dependencies: ["LearningPrimitives"]),
        .testTarget(
            name: "LearningCoreTests",
            dependencies: ["LearningCore"],
            resources: [.copy("Fixtures")]
        ),
    ]
)
