// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "safari-cli",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "safari", path: "Sources/safari")
    ]
)
