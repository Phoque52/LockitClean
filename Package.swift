// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "LockitClean",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(name: "LockitClean", path: "Sources/LockitClean")
    ]
)
