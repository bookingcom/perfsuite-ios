//
//  OTelInstrumenterTests.swift
//  PerformanceSuiteOTel-Tests
//
//  Created by Ahmed Nafei on 30/04/2026.
//

// SwiftLint: this suite exhaustively covers every signal's live + completed-fallback path through
// one instrumenter, so the file/type bodies run long. AGENTS.md permits SwiftLint escapes in tests.
// swiftlint:disable file_length type_body_length

import OpenTelemetryApi
@testable import PerformanceSuite
import UIKit
import XCTest

// In SwiftPM `PerformanceSuiteOTel` is its own module, so we testably import
// it. In CocoaPods all OTel sources are part of `PerformanceSuite` and are
// already exposed by the testable import above.
#if canImport(PerformanceSuiteOTel)
@testable import PerformanceSuiteOTel
#endif

/// Identifier enum used to verify that ``OTelInstrumenter`` extracts
/// `rawValue` for `String`-backed `RawRepresentable` enums (the common case
/// in the host app).
private enum TestScreen: String {
    case homescreen
    case searchResults = "search_results"
}

/// Identifier without a `String` raw value — exercises the
/// `String(describing:)` fallback path.
private enum TestFragment: Equatable {
    case header
    case footer
}

/// File-scope so `String(describing: type(of:))` yields the clean class name
/// "SampleViewController" (a function-local class would mangle to "… #1 in …").
private final class SampleViewController: UIViewController {}

@available(iOS 16.0, *)
final class OTelInstrumenterTests: XCTestCase {

    // MARK: - Test setup helpers

    /// Build an instrumenter that uses the supplied `MockTracerProvider` and a
    /// fixed `now` clock so we can verify `start = end - duration` exactly,
    /// without flakiness from real time passing during the test.
    private func makeInstrumenter(
        provider: MockTracerProvider,
        loggerProvider: MockLoggerProvider? = nil,
        attributeProvider: OTelAttributeProvider? = nil,
        autoTerminationAttribute: (key: String, value: String)? = nil,
        now: Date = Date(timeIntervalSince1970: 1_700_000_000)
    ) -> OTelInstrumenter<TestScreen, TestFragment> {
        OTelInstrumenter<TestScreen, TestFragment>(
            screenIdentifier: nil,
            tracerProvider: provider,
            loggerProvider: loggerProvider,
            instrumentationName: "perfsuite-ios",
            instrumentationVersion: "1.7.0",
            attributeProvider: attributeProvider,
            autoTerminationAttribute: autoTerminationAttribute,
            now: { now }
        )
    }

    private func metrics(tti ms: Int, ttfr ttfrMs: Int = 50) -> TTIMetrics {
        TTIMetrics(
            tti: .milliseconds(ms),
            ttfr: .milliseconds(ttfrMs),
            appStartInfo: .empty
        )
    }

    private func renderingMetrics(sessionMs: Int = 4_000) -> RenderingMetrics {
        RenderingMetrics(
            renderedFrames: 240,
            expectedFrames: 240,
            droppedFrames: 5,
            frozenFrames: 0,
            slowFrames: 7,
            freezeTime: .milliseconds(120),
            sessionDuration: .milliseconds(sessionMs),
            appStartInfo: .empty
        )
    }

    private func startupData(prewarmed: Bool, totalMs: Int = 1_500) -> StartupTimeData {
        StartupTimeData(
            totalTime: .milliseconds(totalMs),
            preMainTime: .milliseconds(300),
            mainTime: .milliseconds(1_200),
            totalBeforeViewControllerTime: .milliseconds(900),
            mainBeforeViewControllerTime: .milliseconds(600),
            appStartInfo: AppStartInfo(appStartedWithPrewarming: prewarmed)
        )
    }

    // MARK: - App rendering

    func testAppRenderingSpanIsScreenless() throws {
        let provider = MockTracerProvider()
        let instrumenter = makeInstrumenter(provider: provider)

        instrumenter.appRenderingSessionStarted(at: Date(timeIntervalSince1970: 1_700_000_000))
        instrumenter.appRenderingMetricsReceived(metrics: renderingMetrics(sessionMs: 2_000))
        instrumenter.appRenderingSessionEnded()

        let builder = try XCTUnwrap(provider.tracer.lastBuilder)
        XCTAssertEqual(builder.spanName, "app-rendering")
        // Live-span shape: rendering counters are applied to the started span via
        // `setAttribute` (not on the builder), both at per-chunk update and at finalize.
        let span = try XCTUnwrap(builder.startedSpan)
        XCTAssertNil(span.attributes["screen.name"])
        XCTAssertEqual(span.attributes["rendering.session_duration.ms"]?.intValue, 2_000)
    }

    // MARK: - Hangs

    func testFatalHangEmitsAppHangSpanWithFatalType() throws {
        let provider = MockTracerProvider()
        let instrumenter = makeInstrumenter(provider: provider)
        let info = HangInfo.with(callStack: "stack", duringStartup: false, duration: .milliseconds(2_500))

        instrumenter.fatalHangReceived(info: info)

        let builder = try XCTUnwrap(provider.tracer.lastBuilder)
        XCTAssertEqual(builder.spanName, "app-hang")
        XCTAssertEqual(builder.attributes["hang.type"]?.stringValue, "fatal")
        XCTAssertEqual(builder.attributes["hang.duration.ms"]?.intValue, 2_500)
        XCTAssertEqual(builder.attributes["hang.during_startup"]?.boolValue, false)
    }

    func testHangStartedOpensLiveHangSpan() throws {
        // hangStarted opens a live `app-hang` span anchored on
        // info.detectedAt. The matching nonFatalHangReceived (or fatal-hang
        // detected on next launch) finalises it. Test the live-span START
        // here — `testNonFatalHangFinalisesLiveHangSpan` covers the end.
        let provider = MockTracerProvider()
        let instrumenter = makeInstrumenter(provider: provider)
        let detectedAt = Date(timeIntervalSince1970: 1_700_000_010)
        let info = HangInfo.with(
            callStack: "stack",
            duringStartup: false,
            duration: .milliseconds(2_000),
            detectedAt: detectedAt,
            sessionId: "session-A"
        )

        instrumenter.hangStarted(info: info)

        let builder = try XCTUnwrap(provider.tracer.lastBuilder)
        XCTAssertEqual(builder.spanName, "app-hang")
        XCTAssertEqual(builder.startTime, detectedAt,
                       "Live hang span anchors on info.detectedAt — matches the completed-span shape")
        XCTAssertEqual(builder.attributes["hang.during_startup"]?.boolValue, false)
        XCTAssertEqual(builder.attributes["app.session.id"]?.stringValue, "session-A")
        let span = try XCTUnwrap(builder.startedSpan)
        XCTAssertTrue(span.isRecording, "Live span stays open until matching hangReceived")
        XCTAssertFalse(span.ended)
    }

    func testNonFatalHangFinalisesLiveHangSpanWithFinalDuration() throws {
        let provider = MockTracerProvider()
        let instrumenter = makeInstrumenter(provider: provider)
        let detectedAt = Date(timeIntervalSince1970: 1_700_000_010)
        let startInfo = HangInfo.with(
            callStack: "stack",
            duringStartup: false,
            duration: .milliseconds(2_000),
            detectedAt: detectedAt,
            sessionId: "session-A"
        )
        let endInfo = HangInfo.with(
            callStack: "stack",
            duringStartup: false,
            duration: .milliseconds(2_500),
            detectedAt: detectedAt,
            sessionId: "session-A"
        )

        instrumenter.hangStarted(info: startInfo)
        instrumenter.nonFatalHangReceived(info: endInfo)

        XCTAssertEqual(provider.tracer.builders.count, 1, "Same span; not a new one")
        let span = try XCTUnwrap(provider.tracer.lastBuilder?.startedSpan)
        XCTAssertTrue(span.ended)
        XCTAssertEqual(span.attributes["hang.type"]?.stringValue, "non_fatal")
        XCTAssertEqual(span.attributes["hang.duration.ms"]?.intValue, 2_500,
                       "End uses final duration from the nonFatalHangReceived payload")
        // End time = detectedAt + final duration, matching the completed-span shape
        // emitter would produce.
        XCTAssertEqual(span.firstEndTime, detectedAt.addingTimeInterval(2.5))
    }

    // MARK: - Watchdog termination

    func testWatchdogTerminationEmitsPointSpanWithStateAndMemory() throws {
        let provider = MockTracerProvider()
        let instrumenter = makeInstrumenter(provider: provider)
        let data = WatchdogTerminationData(
            applicationState: .active,
            appStartInfo: .empty,
            duringStartup: false,
            memoryWarnings: 4
        )

        instrumenter.watchdogTerminationReceived(data)

        let builder = try XCTUnwrap(provider.tracer.lastBuilder)
        XCTAssertEqual(builder.spanName, "app-watchdog-termination")
        XCTAssertEqual(builder.attributes["memory.warnings_count"]?.intValue, 4)
        XCTAssertNil(builder.attributes["app.state"], "app.state is host-authored via attributeProvider")
        XCTAssertNil(builder.attributes["device.ram.mb"], "device.ram.mb is host-authored via attributeProvider")
        XCTAssertNil(builder.attributes["os.name"], "Device/OS attributes are host-authored via attributeProvider")
        XCTAssertNil(builder.attributes["os.version"], "Device/OS attributes are host-authored via attributeProvider")
        XCTAssertNil(builder.attributes["device.model"], "Device/OS attributes are host-authored via attributeProvider")

        let span = try XCTUnwrap(builder.startedSpan)
        XCTAssertEqual(span.firstEndTime, builder.startTime,
                       "Watchdog termination is recorded as a zero-duration point in time")
    }

    // MARK: - Tracer provider resolution

    func testTracerProviderReceivesInstrumentationNameAndVersion() {
        let provider = MockTracerProvider()
        let instrumenter = makeInstrumenter(provider: provider)

        _ = instrumenter.startupMeasurementStarted()

        XCTAssertEqual(provider.getCalls.count, 1)
        XCTAssertEqual(provider.getCalls.first?.instrumentationName, "perfsuite-ios")
        XCTAssertEqual(provider.getCalls.first?.instrumentationVersion, "1.7.0")
    }

    func testTracerProviderResolutionIsLazyAcrossEmissions() {
        // The emitter is meant to *re-resolve* the global provider every call so
        // that a late-registered SDK still wins. We verify by emitting twice
        // and asserting two `get` calls reach the provider.
        let provider = MockTracerProvider()
        let instrumenter = makeInstrumenter(provider: provider)

        _ = instrumenter.startupMeasurementStarted()
        instrumenter.appRenderingSessionStarted(at: Date(timeIntervalSince1970: 1_700_000_000))
        instrumenter.appRenderingMetricsReceived(metrics: renderingMetrics())
        instrumenter.appRenderingSessionEnded()

        XCTAssertEqual(provider.getCalls.count, 2,
                       "Each emit should resolve the provider, not cache the tracer at init time")
    }

    // MARK: - screenIdentifier(for:)

    func testScreenIdentifierForViewControllerScreenUsesMainBundleDefault() {
        // When Screen == UIViewController and no closure is provided, the
        // instrumenter mirrors PerformanceSuite's default of tracking only
        // main-bundle view controllers.
        let instrumenter = OTelInstrumenter<UIViewController, String>()

        // System UIViewController is in UIKit's bundle, not the main bundle.
        XCTAssertNil(instrumenter.screenIdentifier(for: UIViewController()))
    }

    func testScreenIdentifierForGenericScreenWithoutClosureReturnsNil() {
        let instrumenter = OTelInstrumenter<TestScreen, TestFragment>()

        XCTAssertNil(
            instrumenter.screenIdentifier(for: UIViewController()),
            "Without a closure, a typed Screen has no way to map a VC and must return nil"
        )
    }

    func testScreenIdentifierUsesProvidedClosure() {
        let provider = MockTracerProvider()
        let viewController = UIViewController()
        var captured: UIViewController?
        let instrumenter = OTelInstrumenter<TestScreen, TestFragment>(
            screenIdentifier: { vc in
                captured = vc
                return .homescreen
            },
            tracerProvider: provider
        )

        let mapped = instrumenter.screenIdentifier(for: viewController)

        XCTAssertEqual(mapped, .homescreen)
        XCTAssertTrue(captured === viewController)
    }

    // MARK: - Live spans: TTI

    func testScreenTTIMeasurementStartedReturnsLiveContextAndOpensSpan() throws {
        let provider = MockTracerProvider()
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let instrumenter = makeInstrumenter(provider: provider, now: now)

        let context = instrumenter.screenTTIMeasurementStarted(screen: .searchResults)

        XCTAssertNotNil(context, "Live receiver returns a non-nil context for screen TTI")
        let builder = try XCTUnwrap(provider.tracer.lastBuilder)
        XCTAssertEqual(builder.spanName, "screen-tti.search_results",
                       "Live span name uses rawValue, same as completed-span path")
        XCTAssertEqual(builder.startTime, now)
        XCTAssertEqual(builder.attributes["screen.name"]?.stringValue, "search_results")
        let span = try XCTUnwrap(builder.startedSpan)
        XCTAssertTrue(span.isRecording, "Live span stays open until ended")
        XCTAssertFalse(span.ended)
    }

    func testScreenTTIMeasurementEndedFinalisesLiveSpanWithTimingAttributes() throws {
        let provider = MockTracerProvider()
        let instrumenter = makeInstrumenter(provider: provider)

        let context = instrumenter.screenTTIMeasurementStarted(screen: .homescreen)
        instrumenter.screenTTIMeasurementEnded(
            metrics: metrics(tti: 800, ttfr: 50),
            screen: .homescreen,
            context: context
        )

        let span = try XCTUnwrap(provider.tracer.lastBuilder?.startedSpan)
        XCTAssertTrue(span.ended)
        XCTAssertEqual(span.attributes["screen.tti.ms"]?.intValue, 800)
        XCTAssertEqual(span.attributes["screen.ttfr.ms"]?.intValue, 50)
    }

    func testScreenTTIMeasurementEndedWithNilContextEmitsNothing() throws {
        // Live-only: a nil context (e.g. shouldEmit rejected at start) must NOT fall back to a
        // completed span — that would bypass shouldEmit.
        let provider = MockTracerProvider()
        let instrumenter = makeInstrumenter(provider: provider)

        instrumenter.screenTTIMeasurementEnded(
            metrics: metrics(tti: 800),
            screen: .homescreen,
            context: nil
        )

        XCTAssertNil(provider.tracer.lastBuilder, "No span is emitted without a live context")
    }

    func testScreenTTILiveSpanCancelClosesWithErrorStatus() throws {
        let provider = MockTracerProvider()
        let instrumenter = makeInstrumenter(provider: provider)

        let context = instrumenter.screenTTIMeasurementStarted(screen: .homescreen)
        let unwrapped = try XCTUnwrap(context)
        unwrapped.cancel()

        let span = try XCTUnwrap(provider.tracer.lastBuilder?.startedSpan)
        XCTAssertTrue(span.ended)
        if case let .error(description) = span.status {
            XCTAssertEqual(description, "measurement_cancelled")
        } else {
            XCTFail("Cancelled span must end with Status.error")
        }
    }

    // MARK: - Live spans: Screen rendering

    func testScreenRenderingStartedAnchorsLiveSpanOnSessionStartedDate() throws {
        let provider = MockTracerProvider()
        let instrumenter = makeInstrumenter(provider: provider)
        let viewDidAppearAt = Date(timeIntervalSince1970: 1_700_000_500)

        let context = instrumenter.screenRenderingStarted(
            screen: .homescreen,
            sessionStarted: viewDidAppearAt
        )

        XCTAssertNotNil(context)
        let builder = try XCTUnwrap(provider.tracer.lastBuilder)
        XCTAssertEqual(
            builder.startTime, viewDidAppearAt,
            "live span's setStartTime is the wall-clock Date captured pre-async-hop"
        )
        XCTAssertEqual(builder.spanName, "screen-rendering.homescreen")
    }

    func testScreenRenderingEndedFinalisesLiveSpanWithCounters() throws {
        let provider = MockTracerProvider()
        let instrumenter = makeInstrumenter(provider: provider)

        let context = instrumenter.screenRenderingStarted(
            screen: .homescreen,
            sessionStarted: Date(timeIntervalSince1970: 1_700_000_000)
        )
        instrumenter.screenRenderingEnded(
            metrics: renderingMetrics(sessionMs: 4_000),
            screen: .homescreen,
            context: context
        )

        let span = try XCTUnwrap(provider.tracer.lastBuilder?.startedSpan)
        XCTAssertTrue(span.ended)
        XCTAssertEqual(span.attributes["rendering.dropped_frames"]?.intValue, 5)
        XCTAssertEqual(span.attributes["rendering.session_duration.ms"]?.intValue, 4_000)
    }

    // MARK: - Live spans: Fragment TTI

    func testFragmentTTIMeasurementStartedReturnsLiveContext() throws {
        let provider = MockTracerProvider()
        let instrumenter = makeInstrumenter(provider: provider)

        let context = instrumenter.fragmentTTIMeasurementStarted(fragment: .header)

        XCTAssertNotNil(context)
        let builder = try XCTUnwrap(provider.tracer.lastBuilder)
        XCTAssertEqual(builder.spanName, "fragment-tti.header")
        XCTAssertEqual(builder.attributes["fragment.name"]?.stringValue, "header")
    }

    func testFragmentTTIMeasurementEndedFinalisesLiveSpan() throws {
        let provider = MockTracerProvider()
        let instrumenter = makeInstrumenter(provider: provider)

        let context = instrumenter.fragmentTTIMeasurementStarted(fragment: .footer)
        instrumenter.fragmentTTIMeasurementEnded(
            metrics: metrics(tti: 1_200, ttfr: 100),
            fragment: .footer,
            context: context
        )

        let span = try XCTUnwrap(provider.tracer.lastBuilder?.startedSpan)
        XCTAssertTrue(span.ended)
        XCTAssertEqual(span.attributes["fragment.tti.ms"]?.intValue, 1_200)
        XCTAssertEqual(span.attributes["fragment.ttfr.ms"]?.intValue, 100)
    }

    // MARK: - Live spans: Startup

    func testStartupMeasurementStartedAnchorsLiveSpanOnProcessStartTime() throws {
        let provider = MockTracerProvider()
        let instrumenter = makeInstrumenter(provider: provider)

        let context = instrumenter.startupMeasurementStarted()

        XCTAssertNotNil(context)
        let builder = try XCTUnwrap(provider.tracer.lastBuilder)
        XCTAssertEqual(builder.spanName, "app-startup")
        XCTAssertEqual(
            builder.startTime, PerformanceMonitoring.processStartTime,
            "Live startup span anchors retroactively on sysctl-reported process start"
        )
        XCTAssertNil(builder.attributes["app.startup.total_time.ms"],
                     "Startup attributes are deferred to startupMeasurementEnded")
    }

    func testStartupMeasurementEndedFinalisesLiveSpanWithTimingAttributes() throws {
        let provider = MockTracerProvider()
        let instrumenter = makeInstrumenter(provider: provider)

        let context = instrumenter.startupMeasurementStarted()
        instrumenter.startupMeasurementEnded(startupData(prewarmed: false), context: context)

        XCTAssertEqual(provider.tracer.builders.count, 1, "Live start+end produce exactly one span, not two")
        let span = try XCTUnwrap(provider.tracer.lastBuilder?.startedSpan)
        XCTAssertTrue(span.ended)
        XCTAssertEqual(span.attributes["app.startup.total_time.ms"]?.intValue, 1_500)
        XCTAssertEqual(span.attributes["app.startup.main_time.ms"]?.intValue, 1_200)
        XCTAssertEqual(span.attributes["app.startup.premain_time.ms"]?.intValue, 300)
        XCTAssertEqual(span.attributes["app.startup.prewarmed"]?.boolValue, false)
    }

    // MARK: - identifierName

    func testViewControllerScreenNameUsesClassNameNotInstancePointer() throws {
        // Screen name must be the stable class name, not String(describing: instance) which embeds the heap pointer.
        let provider = MockTracerProvider()
        let instrumenter = OTelInstrumenter<UIViewController, String>(tracerProvider: provider)

        _ = instrumenter.screenTTIMeasurementStarted(screen: SampleViewController())

        let builder = try XCTUnwrap(provider.tracer.lastBuilder)
        XCTAssertEqual(builder.spanName, "screen-tti.SampleViewController")
        XCTAssertEqual(builder.attributes["screen.name"]?.stringValue, "SampleViewController")
        XCTAssertFalse(builder.spanName.contains("0x"), "Span name must not embed an instance pointer")
    }

    // MARK: - Auto-termination injection

    func testInjectedAutoTerminationAttributeIsStampedOnUncleanExitLiveSpans() throws {
        let provider = MockTracerProvider()
        let instrumenter = makeInstrumenter(
            provider: provider,
            autoTerminationAttribute: (key: "emb.auto_termination.code", value: "user_abandon")
        )

        // Raw live span (startup) and start-gated live span (screen TTI) both get it at start —
        // their unclean-exit case has no other record, so the orphan is the only capture.
        _ = instrumenter.startupMeasurementStarted()
        let startupBuilder = try XCTUnwrap(provider.tracer.lastBuilder)
        XCTAssertEqual(startupBuilder.attributes["emb.auto_termination.code"]?.stringValue, "user_abandon")

        _ = instrumenter.screenTTIMeasurementStarted(screen: .homescreen)
        let ttiBuilder = try XCTUnwrap(provider.tracer.lastBuilder)
        XCTAssertEqual(ttiBuilder.attributes["emb.auto_termination.code"]?.stringValue, "user_abandon")
    }

    func testHangLiveSpanOmitsAutoTerminationAttribute() throws {
        let provider = MockTracerProvider()
        let instrumenter = makeInstrumenter(
            provider: provider,
            autoTerminationAttribute: (key: "emb.auto_termination.code", value: "user_abandon")
        )

        // A fatal hang already has an authoritative next-launch record (fatalHangReceived), so the
        // hang live span must NOT carry auto-termination — otherwise Embrace's auto-terminated orphan
        // double-counts it. Without the attribute Embrace drops the unended span on the dying session.
        instrumenter.hangStarted(info: HangInfo.with(callStack: "s", duringStartup: false, duration: .milliseconds(2_000)))

        let builder = try XCTUnwrap(provider.tracer.lastBuilder)
        XCTAssertEqual(builder.spanName, "app-hang")
        XCTAssertNil(builder.attributes["emb.auto_termination.code"],
                     "Hang live span must not carry auto-termination — the fatal record comes next launch")
    }

    func testPostFactoSpanDoesNotCarryAutoTerminationAttribute() throws {
        let provider = MockTracerProvider()
        let instrumenter = makeInstrumenter(
            provider: provider,
            autoTerminationAttribute: (key: "emb.auto_termination.code", value: "user_abandon")
        )

        // Post-facto spans (watchdog, fatal hang) go through `emitSpan`, not the live builder —
        // auto-termination is meaningless there.
        instrumenter.watchdogTerminationReceived(
            WatchdogTerminationData(applicationState: .active, appStartInfo: .empty, duringStartup: false, memoryWarnings: 1)
        )

        let builder = try XCTUnwrap(provider.tracer.lastBuilder)
        XCTAssertNil(builder.attributes["emb.auto_termination.code"])
    }
}
