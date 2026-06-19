//
//  RenderingMetricsTests.swift
//  PerformanceSuite-Tests
//

@testable import PerformanceSuite
import XCTest

/// Covers RenderingMetrics.sessionStarted anchor propagation through the + operator and the zero factories.
final class RenderingMetricsTests: XCTestCase {

    private let referenceDate = Date(timeIntervalSince1970: 1_700_000_000)

    private func metrics(
        droppedFrames: Int = 0,
        sessionDurationMs: Int = 0,
        sessionStarted: Date? = nil
    ) -> RenderingMetrics {
        RenderingMetrics(
            renderedFrames: 0,
            expectedFrames: 0,
            droppedFrames: droppedFrames,
            frozenFrames: 0,
            slowFrames: 0,
            freezeTime: .zero,
            sessionDuration: .milliseconds(sessionDurationMs),
            appStartInfo: .empty,
            sessionStarted: sessionStarted
        )
    }

    func testZeroFactories() {
        XCTAssertNil(RenderingMetrics.zero.sessionStarted)

        let anchored = RenderingMetrics.zero(sessionStarted: referenceDate)
        XCTAssertEqual(anchored.sessionStarted, referenceDate)
        XCTAssertEqual(anchored.droppedFrames, 0,
                       "All counter fields stay at zero — only the anchor is set")
    }

    func testFrameMetricsFactoryLeavesSessionStartedNil() {
        let frame = RenderingMetrics.metrics(frameDuration: 0.020, refreshRateDuration: 0.0167)

        XCTAssertNil(frame.sessionStarted)
    }

    func testPlusOperatorPropagatesEarlierNonNilSessionStarted() {
        let earlier = referenceDate
        let later = referenceDate.addingTimeInterval(5)
        let lhs = metrics(droppedFrames: 1, sessionDurationMs: 100, sessionStarted: earlier)
        let rhs = metrics(droppedFrames: 2, sessionDurationMs: 200, sessionStarted: later)
        let nilSide = metrics(droppedFrames: 3, sessionDurationMs: 300, sessionStarted: nil)

        XCTAssertEqual((lhs + rhs).sessionStarted, earlier,
                       "Earlier non-nil wins — accumulator + new chunk preserves the older anchor")
        XCTAssertEqual((rhs + lhs).sessionStarted, later,
                       "Operator is left-leaning: lhs.sessionStarted ?? rhs.sessionStarted")
        XCTAssertEqual((lhs + nilSide).sessionStarted, earlier)
        XCTAssertEqual((nilSide + lhs).sessionStarted, earlier)
    }

    func testPlusOperatorEarlyReturnsOnZeroPreserveAnchor() {
        // .zero's anchor is nil; the early-return must still return the OTHER side's anchor.
        let anchored = metrics(droppedFrames: 1, sessionDurationMs: 100, sessionStarted: referenceDate)

        XCTAssertEqual((anchored + .zero).sessionStarted, referenceDate)
        XCTAssertEqual((anchored + .zero).droppedFrames, 1)
        XCTAssertEqual((.zero + anchored).sessionStarted, referenceDate)
        XCTAssertEqual((.zero + anchored).droppedFrames, 1)
    }

    func testZeroFactoryEqualsZeroOnlyWhenAnchorAlsoMatches() {
        // Distinct via Equatable so RenderingObserver's `metrics != .zero` gate can't skip an anchor-only session.
        let bareZero = RenderingMetrics.zero
        let anchoredZero = RenderingMetrics.zero(sessionStarted: referenceDate)

        XCTAssertNotEqual(bareZero, anchoredZero,
                          "An anchored .zero is distinguishable from bare .zero")
    }
}
