// swift-tools-version: 5.7.1

import PackageDescription

let package = Package(
    name: "PerformanceSuite",
    platforms: [
        .iOS(.v15)
    ],
    products: [
        .library(
            name: "PerformanceSuite",
            targets: ["PerformanceSuite"]),
        .library(
            name: "PerformanceSuiteCrashlytics",
            targets: ["PerformanceSuiteCrashlytics"]),
        .library(
            name: "PerformanceSuiteOTel",
            targets: ["PerformanceSuiteOTel"]),
        .executable(
            name: "PerformanceApp",
            targets: ["PerformanceApp"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/firebase/firebase-ios-sdk.git", "10.0.0"..<"13.0.0"),
        .package(url: "https://github.com/yene/GCDWebServer", exact: .init(3, 5, 7)),
        .package(url: "https://github.com/open-telemetry/opentelemetry-swift-core.git", from: "2.0.0"),
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
        .target(
            name: "PerformanceSuiteOTel",
            dependencies: [
                "PerformanceSuite",
                .product(name: "OpenTelemetryApi", package: "opentelemetry-swift-core"),
            ],
            path: "PerformanceSuite/OTel/Sources"
        ),
        .testTarget(
            name: "PerformanceSuiteOTelTests",
            dependencies: [
                "PerformanceSuite",
                "PerformanceSuiteOTel",
                .product(name: "OpenTelemetryApi", package: "opentelemetry-swift-core"),
            ],
            path: "PerformanceSuite/OTel/Tests"
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
