// swift-tools-version: 5.7.1

import PackageDescription

let package = Package(
    name: "PerformanceSuite",
    platforms: [
        .iOS(.v14),
    ],
    products: [
        .library(
            name: "PerformanceSuite",
            targets: ["PerformanceSuite"]),
    ],
    targets: [
        .target(
            name: "PerformanceSuite",
            dependencies: ["MainThreadCallStack"],
            path: "PerformanceSuite/Sources"
        ),
        .target(name: "MainThreadCallStack",
                path: "PerformanceSuite/MainThreadCallStack")
    ]
)
