//
//  OTelAttributeMergeTests.swift
//  PerformanceSuiteOTel-Tests
//
//  Created by Ahmed Nafei on 18/05/2026.
//

import OpenTelemetryApi
@testable import PerformanceSuite
import UIKit
import XCTest

#if canImport(PerformanceSuiteOTel)
@testable import PerformanceSuiteOTel
#endif

/// Centralised tests for the SDK-key guard. The merge helper is shared by
/// every span emission and the leak log emission, so its behaviour is
/// exercised once here on behalf of all callers — the per-emitter tests
/// don't repeat the malicious-host scenario.
final class OTelAttributeMergeTests: XCTestCase {

    private let context: PerformanceSuiteSignalContext = .appRendering(
        AppRenderingContext(
            sessionStartedAt: Date(timeIntervalSince1970: 0),
            sessionEndedAt: Date(timeIntervalSince1970: 1)
        )
    )

    func testReturnsSDKSetUnchangedWhenProviderIsNil() {
        let sdkSet: [String: AttributeValue] = [
            "screen.tti.ms": .int(1_500),
        ]
        let merged = mergeOTelAttributes(
            sdkSet: sdkSet,
            sdkSetKeys: ["screen.tti.ms"],
            provider: nil,
            context: context
        )
        XCTAssertEqual(merged, sdkSet)
    }

    func testHostAttributesNotInReservedKeySetAreIncluded() {
        let sdkSet: [String: AttributeValue] = [
            "screen.tti.ms": .int(1_500),
        ]
        let merged = mergeOTelAttributes(
            sdkSet: sdkSet,
            sdkSetKeys: ["screen.tti.ms"],
            provider: { _ in
                ["EXPS0": .string("abc"), "EXPS1": .string("def")]
            },
            context: context
        )
        XCTAssertEqual(merged["screen.tti.ms"]?.intValue, 1_500)
        XCTAssertEqual(merged["EXPS0"]?.stringValue, "abc")
        XCTAssertEqual(merged["EXPS1"]?.stringValue, "def")
    }

    func testHostAttributesMatchingReservedKeysAreDropped() {
        let sdkSet: [String: AttributeValue] = [
            "app.startup.prewarmed": .bool(false),
            "hang.type": .string("fatal"),
        ]
        let merged = mergeOTelAttributes(
            sdkSet: sdkSet,
            sdkSetKeys: ["app.startup.prewarmed", "hang.type", "memory.warnings_count"],
            provider: { _ in
                [
                    // Malicious host attempting to overwrite SDK-set values.
                    "app.startup.prewarmed": .bool(true),
                    "hang.type": .string("non_fatal"),
                    // Reserved key the SDK didn't set this time but still owns —
                    // host must not be allowed to claim it.
                    "memory.warnings_count": .int(99),
                    // Allowed host attribute.
                    "EXPS0": .string("a"),
                ]
            },
            context: context
        )

        XCTAssertEqual(merged["app.startup.prewarmed"]?.boolValue, false,
                       "Host must not be able to overwrite an SDK-set value")
        XCTAssertEqual(merged["hang.type"]?.stringValue, "fatal",
                       "Host must not be able to overwrite an SDK-set value")
        XCTAssertNil(merged["memory.warnings_count"],
                     "Reserved key not set this emission must still be guarded")
        XCTAssertEqual(merged["EXPS0"]?.stringValue, "a",
                       "Non-reserved host attribute must pass through")
    }

    func testProviderIsInvokedExactlyOnceWithSuppliedContext() {
        var captured: [PerformanceSuiteSignalKind] = []
        _ = mergeOTelAttributes(
            sdkSet: [:],
            sdkSetKeys: [],
            provider: { ctx in
                captured.append(ctx.kind)
                return [:]
            },
            context: .watchdogTermination(WatchdogTerminationData(
                applicationState: .active,
                appStartInfo: .empty,
                duringStartup: false,
                memoryWarnings: 0
            ))
        )
        XCTAssertEqual(captured, [.watchdogTermination])
    }

    func testEmptyHostAttributesProduceSDKSetUnchanged() {
        let sdkSet: [String: AttributeValue] = [
            "hang.duration.ms": .int(1_200),
        ]
        let merged = mergeOTelAttributes(
            sdkSet: sdkSet,
            sdkSetKeys: ["hang.duration.ms", "hang.type"],
            provider: { _ in [:] },
            context: .fatalHang(.with(callStack: "stack", duringStartup: false, duration: .milliseconds(1_200)))
        )
        XCTAssertEqual(merged, sdkSet)
    }
}
