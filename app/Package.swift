// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "CachePilot",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "CachePilot",
            path: "Sources/CachePilot"
        )
    ]
)
