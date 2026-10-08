// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "RunPulse",
    platforms: [.macOS(.v13)],
    dependencies: [.package(url: "https://github.com/PhilRoli/menubar-kit", from: "1.1.0")],
    targets: [
        .executableTarget(
            name: "RunPulse",
            dependencies: [.product(name: "MenuBarKit", package: "menubar-kit")],
            path: "Sources/RunPulse"
        ),
        .testTarget(
            name: "RunPulseTests",
            dependencies: ["RunPulse", .product(name: "MenuBarKit", package: "menubar-kit")],
            path: "Tests/RunPulseTests"
        )
    ]
)
