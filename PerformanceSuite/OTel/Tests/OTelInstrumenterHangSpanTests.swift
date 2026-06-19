//
//  OTelInstrumenterHangSpanTests.swift
//  PerformanceSuiteOTel-Tests
//
//  Created by Ahmed Nafei on 09/06/2026.
//

import OpenTelemetryApi
@testable import PerformanceSuite
import UIKit
import XCTest

#if canImport(PerformanceSuiteOTel)
@testable import PerformanceSuiteOTel
#endif

/// Covers the hang span shape:
///
/// - The window anchors on ``HangInfo/detectedAt`` when present, falling back
///   to `(now - duration, now)` when nil.
/// - The span carries an `app.session.id` attribute sourced from
///   ``HangInfo/sessionId``. The key is reserved in ``OTelSDKKeys/hang``,
///   so a host `attributeProvider` cannot overwrite it.
@available(iOS 16.0, *)
final class OTelInstrumenterHangSpanTests: XCTestCase {

    private enum TestScreen: String {
        case homescreen
    }

    private enum TestFragment: Equatable {
        case header
    }

    private let pinnedNow = Date(timeIntervalSince1970: 1_700_000_000)

    private func makeInstrumenter(
        provider: MockTracerProvider,
        attributeProvider: OTelAttributeProvider? = nil
    ) -> OTelInstrumenter<TestScreen, TestFragment> {
        OTelInstrumenter<TestScreen, TestFragment>(
            screenIdentifier: nil,
            tracerProvider: provider,
            instrumentationName: "perfsuite-ios",
            instrumentationVersion: "1.9.0",
            attributeProvider: attributeProvider,
            now: { self.pinnedNow }
        )
    }

    private func hangInfo(
        durationMs: Int = 2_500,
        detectedAt: Date? = nil,
        sessionId: String? = nil
    ) -> HangInfo {
        HangInfo.with(
            callStack: "stack",
            duringStartup: false,
            duration: .milliseconds(durationMs),
            detectedAt: detectedAt,
            sessionId: sessionId
        )
    }

    // MARK: - Span window anchored on info.detectedAt

    func testHangSpanWindowAnchorsOnDetectedAtWhenPresent() throws {
        let provider = MockTracerProvider()
        let instrumenter = makeInstrumenter(provider: provider)

        // Detected one hour before the pinned `now`. Locks down that the span
        // start sits in the previous-launch window rather than at `now - duration`.
        let detectedAt = pinnedNow.addingTimeInterval(-3_600)
        let info = hangInfo(durationMs: 2_500, detectedAt: detectedAt)

        instrumenter.fatalHangReceived(info: info)

        let builder = try XCTUnwrap(provider.tracer.lastBuilder)
        XCTAssertEqual(builder.startTime, detectedAt,
                       "Fatal hang span startTime should be info.detectedAt, not now() - duration")
        let span = try XCTUnwrap(builder.startedSpan)
        let expectedEnd = detectedAt.addingTimeInterval(2.5)
        XCTAssertEqual(span.firstEndTime, expectedEnd,
                       "Fatal hang span endTime should be detectedAt + duration")
    }

    func testHangSpanFallsBackToNowWindowWhenDetectedAtIsNil() throws {
        let provider = MockTracerProvider()
        let instrumenter = makeInstrumenter(provider: provider)

        // No detectedAt — simulates a HangInfo blob persisted by an older
        // release that did not yet stamp the wall-clock anchor.
        let info = hangInfo(durationMs: 3_000, detectedAt: nil)

        instrumenter.fatalHangReceived(info: info)

        let builder = try XCTUnwrap(provider.tracer.lastBuilder)
        let expectedStart = pinnedNow.addingTimeInterval(-3.0)
        XCTAssertEqual(builder.startTime, expectedStart,
                       "Without detectedAt, the span window is (now - duration, now)")
        let span = try XCTUnwrap(builder.startedSpan)
        XCTAssertEqual(span.firstEndTime, pinnedNow)
    }

    // MARK: - app.session.id attribute

    func testFatalHangSpanCarriesSessionIdAsAttribute() throws {
        let provider = MockTracerProvider()
        let instrumenter = makeInstrumenter(provider: provider)

        let info = hangInfo(sessionId: "previous-session-A")
        instrumenter.fatalHangReceived(info: info)

        let builder = try XCTUnwrap(provider.tracer.lastBuilder)
        XCTAssertEqual(builder.attributes["app.session.id"]?.stringValue, "previous-session-A",
                       "Fatal hang span must surface info.sessionId as app.session.id")
    }

    func testNonFatalHangSpanCarriesSessionIdAsAttribute() throws {
        let provider = MockTracerProvider()
        let instrumenter = makeInstrumenter(provider: provider)

        // Live hang: hangStarted opens the span (stamping app.session.id), nonFatalHangReceived finalises it.
        let info = hangInfo(sessionId: "current-session-B")
        instrumenter.hangStarted(info: info)
        instrumenter.nonFatalHangReceived(info: info)

        let builder = try XCTUnwrap(provider.tracer.lastBuilder)
        XCTAssertEqual(builder.attributes["app.session.id"]?.stringValue, "current-session-B")
    }

    func testHangSpanOmitsSessionIdAttributeWhenInfoSessionIdIsNil() throws {
        let provider = MockTracerProvider()
        let instrumenter = makeInstrumenter(provider: provider)

        let info = hangInfo(sessionId: nil)
        instrumenter.fatalHangReceived(info: info)

        let builder = try XCTUnwrap(provider.tracer.lastBuilder)
        XCTAssertNil(builder.attributes["app.session.id"],
                     "When info.sessionId is nil, no app.session.id attribute should be emitted (no empty string)")
    }

    func testHostAttributeProviderCannotOverwriteSdkSessionId() throws {
        let provider = MockTracerProvider()
        let instrumenter = makeInstrumenter(
            provider: provider,
            attributeProvider: { _ in
                ["app.session.id": .string("malicious-host-value")]
            }
        )

        let info = hangInfo(sessionId: "sdk-session-id")
        instrumenter.fatalHangReceived(info: info)

        let builder = try XCTUnwrap(provider.tracer.lastBuilder)
        XCTAssertEqual(builder.attributes["app.session.id"]?.stringValue, "sdk-session-id",
                       "OTelSDKKeys.hang reserves app.session.id, so a malicious provider cannot overwrite it")
    }
}
