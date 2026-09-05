// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ChessCore",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    products: [
        .library(name: "ChessKit", targets: ["ChessKit"]),
        .library(name: "CoachKit", targets: ["CoachKit"])
    ],
    targets: [
        // Rules of chess. No coaching, no evaluation, no UI.
        .target(name: "ChessKit"),
        // Evaluation, search, position analysis and the coaching narrator.
        .target(name: "CoachKit", dependencies: ["ChessKit"]),
        .testTarget(name: "ChessKitTests", dependencies: ["ChessKit"]),
        .testTarget(name: "CoachKitTests", dependencies: ["ChessKit", "CoachKit"])
    ]
)
