// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "OnAir",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "OnAir", path: "Sources/OnAir")
    ]
)
