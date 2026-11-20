//
//  AppRenderingSessionAccumulatorTests.swift
//  PerformanceSuiteOTel-Tests
//
//  Created by Ahmed Nafei on 09/06/2026.
//

import OpenTelemetryApi
@testable import PerformanceSuite
import XCTest

#if canImport(PerformanceSuiteOTel)
@testable import PerformanceSuiteOTel
#endif

/// Covers ``AppRenderingSessionAccumulator``: `appRenderingSessionStarted(at:)` opens a live span
/// (carrying the injected auto-termination attribute), chunks update cumulative counters on it, and
/// `appRenderingSessionEnded()` finalises it with `app.session.duration.ms`.
final class AppRenderingSessionAccumulatorTests: XCTestCase {

    private let pinnedNow = Date(timeIntervalSince1970: 1_700_000_000)

    private func makeAccumulator(
        provider: MockTracerProvider,
        autoTerminationAttribute: (key: String, value: String)? = ("emb.auto_termination.code", "user_abandon"),
        attributeProvider: OTelAttributeProvider? = nil,
        now: (() -> Date)? = nil
    ) -> AppRenderingSessionAccumulator {
        let nowClosure = now ?? { self.pinnedNow }
        let emitter = OTelSpanEmitter(
            tracerProvider: provider,
            instrumentationName: "perfsuite-ios",
            instrumentationVersion: "1.10.0",
            attributeProvider: attributeProvider,
            autoTerminationAttribute: autoTerminationAttribute,
            now: nowClosure
        )
        return AppRenderingSessionAccumulator(emitter: emitter, now: nowClosure)
    }

    private func renderingMetrics(
        droppedFrames: Int = 5,
        freezeMs: Int = 120,
        sessionMs: Int = 4_000
    ) -> RenderingMetrics {
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

    // MARK: - Live-span lifecycle

    // fixFatalHangOnResignActive: variant test; keep on cleanup, without the experiment setup.
    func testEndingWhileTheStartIsInTheTracerDoesNotWaitAndEndsTheSpanAtTheRequestedTime() throws {
        PerformanceMonitoring.experiments = Experiments(fixFatalHangOnResignActive: true)
        defer {
            PerformanceMonitoring.experiments = Experiments()
        }
        let provider = MockTracerProvider()
        let inStartSpan = DispatchSemaphore(value: 0)
        let finishStartSpan = DispatchSemaphore(value: 0)
        provider.tracer.onStartSpan = {
            inStartSpan.signal()
            finishStartSpan.wait()
        }
        var clock = pinnedNow
        let accumulator = makeAccumulator(provider: provider, now: { clock })
        let started = expectation(description: "session started")
        DispatchQueue.global().async {
            accumulator.appRenderingSessionStarted(
                at: self.pinnedNow, liveMetrics: LiveRenderingMetrics(self.renderingMetrics(sessionMs: 2_000)))
            started.fulfill()
        }
        inStartSpan.wait()
        // Releases the tracer anyway, so a regression fails the test instead of freezing it.
        DispatchQueue.global().asyncAfter(deadline: .now() + 2) {
            finishStartSpan.signal()
        }

        let endRequestedAt = pinnedNow.addingTimeInterval(3)
        clock = endRequestedAt
        let endStarted = Date()
        accumulator.appRenderingSessionEnded()
        XCTAssertLessThan(Date().timeIntervalSince(endStarted), 1, "the end doesn't wait for the tracer")
        clock = endRequestedAt.addingTimeInterval(10)
        finishStartSpan.signal()
        wait(for: [started], timeout: 1)

        let span = try XCTUnwrap(provider.tracer.lastBuilder?.startedSpan)
        XCTAssertEqual(span.endCalls.count, 1, "the requested end runs once the span exists")
        XCTAssertEqual(span.firstEndTime, endRequestedAt, "the span ends when the end was requested")
        XCTAssertEqual(span.attributes["app.session.duration.ms"]?.intValue, 3_000)
        XCTAssertEqual(span.attributes["rendering.session_duration.ms"]?.intValue, 2_000)
    }

    func testSessionStartOpensLiveSpanWithAutoTerminationCode() throws {
        let provider = MockTracerProvider()
        let accumulator = makeAccumulator(provider: provider)

        accumulator.appRenderingSessionStarted(at: pinnedNow)

        XCTAssertEqual(provider.tracer.builders.count, 1, "session start opens exactly one live span")
        let builder = try XCTUnwrap(provider.tracer.lastBuilder)
        XCTAssertEqual(builder.spanName, "app-rendering")
        XCTAssertEqual(builder.startTime, pinnedNow, "Live span anchors at the passed session-start instant")
        XCTAssertEqual(builder.attributes["emb.auto_termination.code"]?.stringValue, "user_abandon")
        let span = try XCTUnwrap(builder.startedSpan, "Span must be started, not just built")
        XCTAssertTrue(span.isRecording)
        XCTAssertFalse(span.ended)

        // Auto-termination code must survive chunk updates (applyRenderingAttributes re-applies the dict).
        accumulator.appRenderingMetricsReceived(metrics: renderingMetrics())
        XCTAssertEqual(span.attributes["emb.auto_termination.code"]?.stringValue, "user_abandon")
    }

    func testPerChunkUpdatesApplyCumulativeAttributesToLiveSpan() throws {
        let provider = MockTracerProvider()
        let accumulator = makeAccumulator(provider: provider)

        accumulator.appRenderingSessionStarted(at: pinnedNow)
        let span = try XCTUnwrap(provider.tracer.lastBuilder?.startedSpan)

        accumulator.appRenderingMetricsReceived(metrics: renderingMetrics(droppedFrames: 5, freezeMs: 100, sessionMs: 2_000))
        XCTAssertEqual(span.attributes["rendering.dropped_frames"]?.intValue, 5)
        XCTAssertEqual(span.attributes["rendering.freeze_time.ms"]?.intValue, 100)

        accumulator.appRenderingMetricsReceived(metrics: renderingMetrics(droppedFrames: 7, freezeMs: 200, sessionMs: 3_000))
        XCTAssertEqual(span.attributes["rendering.dropped_frames"]?.intValue, 12, "Cumulative")
        XCTAssertEqual(span.attributes["rendering.freeze_time.ms"]?.intValue, 300)
        XCTAssertEqual(span.attributes["rendering.session_duration.ms"]?.intValue, 5_000)
        XCTAssertFalse(span.ended)
    }

    func testSessionEndFinalisesLiveSpanWithSessionDuration() throws {
        let provider = MockTracerProvider()
        let activateTime = pinnedNow
        let backgroundTime = pinnedNow.addingTimeInterval(15)

        var clock = activateTime
        let accumulator = makeAccumulator(provider: provider, now: { clock })

        accumulator.appRenderingSessionStarted(at: clock)
        accumulator.appRenderingMetricsReceived(metrics: renderingMetrics(droppedFrames: 4, sessionMs: 8_000))

        clock = backgroundTime
        accumulator.appRenderingSessionEnded()

        let span = try XCTUnwrap(provider.tracer.lastBuilder?.startedSpan)
        XCTAssertTrue(span.ended)
        XCTAssertEqual(span.firstEndTime, backgroundTime)
        XCTAssertEqual(span.status, .unset, "Clean exit — Status.unset, no emb.error_code")
        XCTAssertEqual(span.attributes["app.session.duration.ms"]?.intValue, 15_000)
        XCTAssertEqual(span.attributes["rendering.dropped_frames"]?.intValue, 4)
    }

    // MARK: - Multi-cycle

    func testMultipleSessionCyclesEachOpenAndCloseTheirOwnLiveSpan() throws {
        let provider = MockTracerProvider()
        var clock = pinnedNow
        let accumulator = makeAccumulator(provider: provider, now: { clock })

        accumulator.appRenderingSessionStarted(at: clock)
        accumulator.appRenderingMetricsReceived(metrics: renderingMetrics(droppedFrames: 3, sessionMs: 1_000))
        clock = clock.addingTimeInterval(10)
        accumulator.appRenderingSessionEnded()

        clock = clock.addingTimeInterval(60)
        accumulator.appRenderingSessionStarted(at: clock)
        accumulator.appRenderingMetricsReceived(metrics: renderingMetrics(droppedFrames: 8, sessionMs: 4_000))
        clock = clock.addingTimeInterval(20)
        accumulator.appRenderingSessionEnded()

        XCTAssertEqual(provider.tracer.builders.count, 2)
        let s1 = try XCTUnwrap(provider.tracer.builders[0].startedSpan)
        let s2 = try XCTUnwrap(provider.tracer.builders[1].startedSpan)
        XCTAssertEqual(s1.attributes["rendering.dropped_frames"]?.intValue, 3, "Session 1 carries only its own counter")
        XCTAssertEqual(s2.attributes["rendering.dropped_frames"]?.intValue, 8, "Session 2 reset cleanly between sessions")
        XCTAssertEqual(s1.attributes["app.session.duration.ms"]?.intValue, 10_000)
        XCTAssertEqual(s2.attributes["app.session.duration.ms"]?.intValue, 20_000)
    }

    // MARK: - Edge cases

    func testEmptySessionStillEmitsSpanWithDurationAndZeroCounters() throws {
        let provider = MockTracerProvider()
        var clock = pinnedNow
        let accumulator = makeAccumulator(provider: provider, now: { clock })

        accumulator.appRenderingSessionStarted(at: clock)
        clock = clock.addingTimeInterval(8)
        accumulator.appRenderingSessionEnded()

        let span = try XCTUnwrap(provider.tracer.lastBuilder?.startedSpan)
        XCTAssertTrue(span.ended)
        XCTAssertEqual(span.status, .unset)
        XCTAssertEqual(span.attributes["app.session.duration.ms"]?.intValue, 8_000)
        XCTAssertEqual(span.attributes["rendering.dropped_frames"]?.intValue, 0)
        XCTAssertEqual(span.attributes["rendering.session_duration.ms"]?.intValue, 0)
    }

    func testIdempotentSessionStartDoesNotOpenSecondSpan() throws {
        let provider = MockTracerProvider()
        let accumulator = makeAccumulator(provider: provider)

        accumulator.appRenderingSessionStarted(at: pinnedNow)
        accumulator.appRenderingSessionStarted(at: pinnedNow)
        accumulator.appRenderingSessionStarted(at: pinnedNow)

        XCTAssertEqual(provider.tracer.builders.count, 1, "Only one live span open across stray starts")
    }

    func testStraySessionEndWithNoOpenSessionIsIdempotent() throws {
        let provider = MockTracerProvider()
        let accumulator = makeAccumulator(provider: provider)

        accumulator.appRenderingSessionEnded()
        XCTAssertTrue(provider.tracer.builders.isEmpty)

        accumulator.appRenderingMetricsReceived(metrics: renderingMetrics())
        XCTAssertTrue(provider.tracer.builders.isEmpty)

        accumulator.appRenderingSessionEnded()
        XCTAssertTrue(provider.tracer.builders.isEmpty)
    }

    // MARK: - Auto-termination semantics

    func testNoAutoTerminationAttributeWhenNotInjected() throws {
        let provider = MockTracerProvider()
        let accumulator = makeAccumulator(provider: provider, autoTerminationAttribute: nil)

        accumulator.appRenderingSessionStarted(at: pinnedNow)
        let span = try XCTUnwrap(provider.tracer.lastBuilder?.startedSpan)
        XCTAssertNil(span.attributes["emb.auto_termination.code"])
    }

    func testInjectedAutoTerminationKeyIsReservedAgainstAttributeProvider() throws {
        let provider = MockTracerProvider()
        var clock = pinnedNow
        let accumulator = makeAccumulator(
            provider: provider,
            attributeProvider: { _ in ["emb.auto_termination.code": .string("host_override")] },
            now: { clock }
        )

        accumulator.appRenderingSessionStarted(at: clock)
        clock = clock.addingTimeInterval(5)
        accumulator.appRenderingSessionEnded()

        let span = try XCTUnwrap(provider.tracer.lastBuilder?.startedSpan)
        XCTAssertEqual(span.attributes["emb.auto_termination.code"]?.stringValue, "user_abandon",
                       "SDK-injected value wins; host attributeProvider override is dropped at the reserved-key merge")
    }

    func testNoSpanUntilFirstSessionStartAndPreStartChunksAreDropped() throws {
        let provider = MockTracerProvider()
        let accumulator = makeAccumulator(provider: provider)

        accumulator.appRenderingMetricsReceived(metrics: renderingMetrics(droppedFrames: 9))
        XCTAssertTrue(provider.tracer.builders.isEmpty, "No span before the first session start")
    }
}
