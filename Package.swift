// swift-tools-version:6.2

import PackageDescription

let package = Package(
    name: "RealityVideo",
    platforms: [
        .iOS(.v26)
    ],
    products: [
        .library(
            name: "RealityVideo",
            targets: ["RealityVideo"]),
    ],
    targets: [
        .target(
            name: "RealityVideo"),
        .testTarget(
            name: "RealityVideoTests",
            dependencies: ["RealityVideo"]),
    ]
)
