//
//  HangInfoTests.swift
//  PerformanceSuite-Tests
//
//  Created by Ahmed Nafei on 09/06/2026.
//

import Foundation
import XCTest

@testable import PerformanceSuite

final class HangInfoTests: XCTestCase {

    // MARK: - `with(...)` factory

    func testWithFactoryDefaultsDetectedAtAndSessionIdToNil() {
        let info = HangInfo.with(
            callStack: "stack",
            duringStartup: false,
            duration: .milliseconds(1234)
        )

        XCTAssertNil(info.detectedAt)
        XCTAssertNil(info.sessionId)
        XCTAssertEqual(info.callStack, "stack")
        XCTAssertEqual(info.duringStartup, false)
        XCTAssertEqual(info.duration, .milliseconds(1234))
    }

    func testWithFactoryCapturesDetectedAtAndSessionIdWhenSupplied() {
        let timestamp = Date(timeIntervalSince1970: 1_700_000_000)

        let info = HangInfo.with(
            callStack: "stack",
            duringStartup: true,
            duration: .milliseconds(42),
            detectedAt: timestamp,
            sessionId: "session-A"
        )

        XCTAssertEqual(info.detectedAt, timestamp)
        XCTAssertEqual(info.sessionId, "session-A")
        XCTAssertEqual(info.duringStartup, true)
        XCTAssertEqual(info.duration, .milliseconds(42))
    }

    // MARK: - Codable round-trips

    func testCodableRoundTripPreservesDetectedAtAndSessionId() throws {
        let timestamp = Date(timeIntervalSince1970: 1_700_000_000)
        let original = HangInfo.with(
            callStack: "stack",
            duringStartup: false,
            duration: .milliseconds(5_000),
            detectedAt: timestamp,
            sessionId: "session-XYZ"
        )

        let encoded = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(HangInfo.self, from: encoded)

        XCTAssertEqual(decoded.detectedAt, timestamp)
        XCTAssertEqual(decoded.sessionId, "session-XYZ")
        XCTAssertEqual(decoded.callStack, original.callStack)
        XCTAssertEqual(decoded.duringStartup, original.duringStartup)
        XCTAssertEqual(decoded.duration, original.duration)
    }

    /// `HangInfo` blobs encoded before `detectedAt` and `sessionId` existed
    /// must still decode — both fields should land as `nil`.
    func testDecodingLegacyJsonWithoutNewFieldsSucceedsAndYieldsNil() throws {
        let legacyJSON = Data("""
            {
                "callStack": "legacy stack",
                "architecture": "arm64",
                "iOSVersion": "18.0",
                "appStartInfo": { "appStartedWithPrewarming": false },
                "appRuntimeInfo": { "openedScreens": [] },
                "duringStartup": false,
                "durationInMilliseconds": 1234
            }
            """.utf8)

        let decoded = try JSONDecoder().decode(HangInfo.self, from: legacyJSON)

        XCTAssertNil(decoded.detectedAt)
        XCTAssertNil(decoded.sessionId)
        XCTAssertEqual(decoded.callStack, "legacy stack")
        XCTAssertEqual(decoded.duration, .milliseconds(1234))
    }
}
