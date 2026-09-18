// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "MetalHUDToggle",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "MetalHUDToggle",
            path: "Sources/MetalHUDToggle"
        )
    ]
)
