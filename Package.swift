// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "RunPulse",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "RunPulse",
            path: "Sources/RunPulse"
        ),
        .testTarget(
            name: "RunPulseTests",
            dependencies: ["RunPulse"],
            path: "Tests/RunPulseTests"
        )
    ]
)
