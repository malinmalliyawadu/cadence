// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "TrainingEngine",
    platforms: [.iOS(.v26), .macOS(.v15)],
    products: [
        .library(name: "TrainingEngine", targets: ["TrainingEngine"])
    ],
    targets: [
        .target(name: "TrainingEngine"),
        .testTarget(name: "TrainingEngineTests", dependencies: ["TrainingEngine"])
    ]
)
