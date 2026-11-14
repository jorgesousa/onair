// swift-tools-version:5.10
import PackageDescription

// One module per app: the Mac app is Sources/OnAir + Sources/OnAirCore.
// The iPad app (iPad/OnAir.xcodeproj) compiles Sources/OnAirCore + Sources/OnAirPad.
let package = Package(
    name: "OnAir",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "OnAir", path: "Sources", sources: ["OnAir", "OnAirCore"]),
        .testTarget(name: "OnAirTests", dependencies: ["OnAir"], path: "Tests/OnAirTests"),
    ]
)
