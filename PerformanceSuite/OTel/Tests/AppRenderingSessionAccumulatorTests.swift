//
//  AppRenderingSessionAccumulatorTests.swift
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

/// Covers ``AppRenderingSessionAccumulator``: chunks delivered through
/// `appRenderingMetricsReceived(metrics:)` are buffered between session
/// boundaries, and one OTel span is emitted per session.
final class AppRenderingSessionAccumulatorTests: XCTestCase {

    private let pinnedNow = Date(timeIntervalSince1970: 1_700_000_000)

    private func makeAccumulator(
        provider: MockTracerProvider,
        sessionStartedAt: Date? = nil
    ) -> AppRenderingSessionAccumulator {
        let emitter = OTelSpanEmitter(
            tracerProvider: provider,
            instrumentationName: "perfsuite-ios",
            instrumentationVersion: "1.9.0",
            now: { self.pinnedNow }
        )
        let seed = sessionStartedAt ?? pinnedNow.addingTimeInterval(-30)
        return AppRenderingSessionAccumulator(
            emitter: emitter,
            sessionStartedAt: seed,
            now: { self.pinnedNow }
        )
    }

    private func renderingMetrics(droppedFrames: Int = 5, freezeMs: Int = 120, sessionMs: Int = 4_000) -> RenderingMetrics {
        RenderingMetrics(
            renderedFrames: 240,
            expectedFrames: 240,
            droppedFrames: droppedFrames,
            frozenFrames: 0,
            slowFrames: 7,
            freezeTime: .milliseconds(freezeMs),
            sessionDuration: .milliseconds(sessionMs),
            appStartInfo: .empty
        )
    }

    // MARK: - Session boundary

    func testBuffersChunksAndEmitsOnDidEnterBackground() throws {
        let provider = MockTracerProvider()
        let accumulator = makeAccumulator(provider: provider, sessionStartedAt: pinnedNow.addingTimeInterval(-10))

        // Two chunks arrive during the session.
        accumulator.appRenderingMetricsReceived(metrics: renderingMetrics(droppedFrames: 5, freezeMs: 100, sessionMs: 2_000))
        accumulator.appRenderingMetricsReceived(metrics: renderingMetrics(droppedFrames: 7, freezeMs: 200, sessionMs: 3_000))
        XCTAssertTrue(provider.tracer.builders.isEmpty,
                      "Individual chunks must not emit — only the session boundary does")

        NotificationCenter.default.post(name: UIApplication.didEnterBackgroundNotification, object: nil)

        XCTAssertEqual(provider.tracer.builders.count, 1)
        let builder = try XCTUnwrap(provider.tracer.lastBuilder)
        XCTAssertEqual(builder.spanName, "app-rendering")
        XCTAssertEqual(builder.attributes["rendering.dropped_frames"]?.intValue, 12)
        XCTAssertEqual(builder.attributes["rendering.freeze_time.ms"]?.intValue, 300)
        XCTAssertEqual(builder.attributes["rendering.session_duration.ms"]?.intValue, 5_000)
        XCTAssertEqual(builder.attributes["app.session.duration.ms"]?.intValue, 10_000,
                       "app.session.duration.ms is wall-clock sessionEndedAt - sessionStartedAt")
    }

    func testHandlesMultipleSessionCycles() throws {
        let provider = MockTracerProvider()
        let accumulator = makeAccumulator(provider: provider)

        // Session 1: ends with the seeded anchor.
        accumulator.appRenderingMetricsReceived(metrics: renderingMetrics(droppedFrames: 3, freezeMs: 50, sessionMs: 1_000))
        NotificationCenter.default.post(name: UIApplication.didEnterBackgroundNotification, object: nil)

        // Session 2: didBecomeActive sets a fresh anchor.
        NotificationCenter.default.post(name: UIApplication.didBecomeActiveNotification, object: nil)
        accumulator.appRenderingMetricsReceived(metrics: renderingMetrics(droppedFrames: 8, freezeMs: 250, sessionMs: 4_000))
        NotificationCenter.default.post(name: UIApplication.didEnterBackgroundNotification, object: nil)

        XCTAssertEqual(provider.tracer.builders.count, 2)
        XCTAssertEqual(provider.tracer.builders[0].attributes["rendering.dropped_frames"]?.intValue, 3,
                       "Session 1 carries only its own chunk")
        XCTAssertEqual(provider.tracer.builders[1].attributes["rendering.dropped_frames"]?.intValue, 8,
                       "Session 2's accumulator is reset cleanly between sessions")
        XCTAssertEqual(provider.tracer.builders[1].attributes["rendering.freeze_time.ms"]?.intValue, 250)
    }

    // MARK: - Anchoring

    func testFirstSessionUsesSeededLaunchAnchorEvenWhenDidBecomeActiveIsMissed() throws {
        // Simulates the case where the host calls `enable(...)` after
        // `didBecomeActive` has already fired — the observer never sees the
        // notification. The seeded `sessionStartedAt` keeps the first session
        // emittable.
        let provider = MockTracerProvider()
        let launchTime = pinnedNow.addingTimeInterval(-60)
        let accumulator = makeAccumulator(provider: provider, sessionStartedAt: launchTime)

        accumulator.appRenderingMetricsReceived(metrics: renderingMetrics(droppedFrames: 4, freezeMs: 80, sessionMs: 2_000))
        NotificationCenter.default.post(name: UIApplication.didEnterBackgroundNotification, object: nil)

        let builder = try XCTUnwrap(provider.tracer.lastBuilder)
        XCTAssertEqual(builder.startTime, launchTime,
                       "First session anchors on the seeded launch time when no didBecomeActive was observed")
        XCTAssertEqual(builder.attributes["app.session.duration.ms"]?.intValue, 60_000)
    }

    func testDidBecomeActiveDoesNotOverwriteSeededLaunchAnchor() throws {
        // The first session keeps its launch-time anchor even if a stray
        // `didBecomeActive` arrives during the session (e.g. a foreground
        // event posted while the app was already active).
        let provider = MockTracerProvider()
        let launchTime = pinnedNow.addingTimeInterval(-100)
        let accumulator = makeAccumulator(provider: provider, sessionStartedAt: launchTime)

        NotificationCenter.default.post(name: UIApplication.didBecomeActiveNotification, object: nil)
        accumulator.appRenderingMetricsReceived(metrics: renderingMetrics())
        NotificationCenter.default.post(name: UIApplication.didEnterBackgroundNotification, object: nil)

        let builder = try XCTUnwrap(provider.tracer.lastBuilder)
        XCTAssertEqual(builder.startTime, launchTime)
    }

    // MARK: - Edge cases

    func testSkipsEmissionForEmptySessions() throws {
        let provider = MockTracerProvider()
        let accumulator = makeAccumulator(provider: provider)
        _ = accumulator // hold reference

        // didEnterBackground without any accumulated chunks.
        NotificationCenter.default.post(name: UIApplication.didEnterBackgroundNotification, object: nil)

        XCTAssertTrue(provider.tracer.builders.isEmpty,
                      "Empty sessions emit no span")
    }

    func testIgnoresStrayBackgroundWithNoOpenSession() throws {
        let provider = MockTracerProvider()
        let accumulator = makeAccumulator(provider: provider)

        // First didEnterBackground clears the seeded anchor (and emits nothing
        // because no chunks accumulated). A second didEnterBackground without
        // a foreground in between has no anchor and emits nothing.
        NotificationCenter.default.post(name: UIApplication.didEnterBackgroundNotification, object: nil)
        accumulator.appRenderingMetricsReceived(metrics: renderingMetrics())
        NotificationCenter.default.post(name: UIApplication.didEnterBackgroundNotification, object: nil)

        XCTAssertTrue(provider.tracer.builders.isEmpty)
    }
}
