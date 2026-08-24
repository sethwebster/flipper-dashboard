// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "FlipperDashboard",
    platforms: [
        .macOS(.v13),
    ],
    products: [
        .executable(name: "FlipperDashboard", targets: ["DashboardBar"]),
    ],
    targets: [
        .target(name: "FlipperIRCore"),
        .executableTarget(name: "DashboardBar", dependencies: ["FlipperIRCore"]),
        .testTarget(name: "FlipperIRCoreTests", dependencies: ["FlipperIRCore"]),
        .testTarget(
            name: "DashboardBarTests",
            dependencies: ["DashboardBar", "FlipperIRCore"]
        ),
    ]
)
