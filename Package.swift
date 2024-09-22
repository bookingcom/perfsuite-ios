// swift-tools-version: 5.7.1

import PackageDescription

let package = Package(
    name: "PerformanceSuite",
    platforms: [
        .iOS(.v14)
    ],
    products: [
        .library(
            name: "PerformanceSuite",
            targets: ["PerformanceSuite"]),
        .library(
            name: "PerformanceSuiteCrashlytics",
            targets: ["PerformanceSuiteCrashlytics"]),
        .executable(
            name: "PerformanceApp",
            targets: ["PerformanceApp"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/firebase/firebase-ios-sdk.git", from: .init(10, 0, 0)),
        .package(url: "https://github.com/yene/GCDWebServer", exact: .init(3, 5, 7)),
    ],
    targets: [
        .target(
            name: "PerformanceSuite",
            dependencies: ["MainThreadCallStack"],
            path: "PerformanceSuite/Sources"
        ),
        .target(
            name: "PerformanceSuiteCrashlytics",
            dependencies: [
                "PerformanceSuite",
                "MainThreadCallStack",
                "CrashlyticsImports",
                .product(name: "FirebaseCrashlytics", package: "firebase-ios-sdk"),
            ],
            path: "PerformanceSuite/Crashlytics/Sources"
        ),
        .target(name: "CrashlyticsImports",
                dependencies: [
                    .product(name: "FirebaseCrashlytics", package: "firebase-ios-sdk")
                ],
                path: "PerformanceSuite/Crashlytics/Imports"),
        .target(name: "MainThreadCallStack",
                path: "PerformanceSuite/MainThreadCallStack"),

        .executableTarget(
            name: "PerformanceApp",
            dependencies: [
                "PerformanceSuite",
                "PerformanceSuiteCrashlytics",
                .product(name: "GCDWebServer", package: "GCDWebServer"),
            ],
            path: "PerformanceSuite/PerformanceApp"
        ),
    ]
)
