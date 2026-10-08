// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MirrorLens",
    platforms: [
        .macOS(.v13)
    ],
    targets: [
        .executableTarget(
            name: "MirrorLens",
            path: "Sources/MirrorLens"
        )
    ]
)
