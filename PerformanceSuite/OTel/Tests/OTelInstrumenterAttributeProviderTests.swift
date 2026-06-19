//
//  OTelInstrumenterAttributeProviderTests.swift
//  PerformanceSuiteOTel-Tests
//
//  Created by Ahmed Nafei on 18/05/2026.
//

// SwiftLint: tests for `OTelInstrumenter`'s attribute-provider hook + leak
// log emission share enough fixtures (`AttributeProviderSpy`, deterministic
// helpers, stub view controllers) that consolidating them in one file is
// clearer than splitting again. Both size limits are crossed by reasonable
// test scaffolding; AGENTS.md permits SwiftLint escapes in test code.
// swiftlint:disable file_length type_body_length

import OpenTelemetryApi
@testable import PerformanceSuite
import UIKit
import XCTest

#if canImport(PerformanceSuiteOTel)
@testable import PerformanceSuiteOTel
#endif

/// Identifier enum used to verify ``OTelInstrumenter`` extracts `rawValue` for
/// `String`-backed `RawRepresentable` enums (the common case in the host app).
private enum TestScreen: String {
    case homescreen
    case searchResults = "search_results"
}

private enum TestFragment: Equatable {
    case header
    case footer
}

// MARK: - File-scope test fixtures
//
// Flattened to file scope (rather than nested inside the test class) to keep
// every type at most one level deep — SwiftLint's `nesting` rule.

private struct AttributeProviderSpyCapture {
    let kind: PerformanceSuiteSignalKind
    let screenName: String?
    let fragmentName: String?
    let hangFatality: AttributeProviderSpyHangFatality?
    let leakedViewController: UIViewController?
}

private enum AttributeProviderSpyHangFatality { case fatal, nonFatal }

/// Captures every `(kind, sample-fields)` tuple the attribute provider receives
/// so each per-signal test can assert that its emission reached the provider
/// with the right context shape.
private final class AttributeProviderSpy {

    private(set) var captures: [AttributeProviderSpyCapture] = []
    var attributesToReturn: [String: AttributeValue] = [:]

    func makeProvider() -> OTelAttributeProvider {
        { [weak self] context in
            guard let self else { return [:] }
            self.captures.append(Self.capture(from: context))
            return self.attributesToReturn
        }
    }

    private static func capture(from context: PerformanceSuiteSignalContext) -> AttributeProviderSpyCapture {
        let screenName: String?
        let fragmentName: String?
        let hangFatality: AttributeProviderSpyHangFatality?
        let leakedViewController: UIViewController?
        switch context {
        case .startup, .appRendering, .watchdogTermination:
            screenName = nil; fragmentName = nil
            hangFatality = nil; leakedViewController = nil
        case .screenTTI(let ctx), .screenRendering(let ctx):
            screenName = ctx.screenName; fragmentName = nil
            hangFatality = nil; leakedViewController = nil
        case .fragmentTTI(let ctx):
            screenName = nil; fragmentName = ctx.fragmentName
            hangFatality = nil; leakedViewController = nil
        case .fatalHang:
            screenName = nil; fragmentName = nil
            hangFatality = .fatal; leakedViewController = nil
        case .nonFatalHang:
            screenName = nil; fragmentName = nil
            hangFatality = .nonFatal; leakedViewController = nil
        case .viewControllerLeak(let viewController):
            screenName = nil; fragmentName = nil
            hangFatality = nil; leakedViewController = viewController
        }
        return AttributeProviderSpyCapture(
            kind: context.kind,
            screenName: screenName,
            fragmentName: fragmentName,
            hangFatality: hangFatality,
            leakedViewController: leakedViewController
        )
    }
}

/// Stub conformer to ``RootViewIntrospectable`` used to test SwiftUI-style
/// class-name refinement. Its introspected root view drives `vc.class_name`
/// when the view controller conforms.
private final class StubHostingController: UIViewController, RootViewIntrospectable {
    func introspectRootView() -> Any { StubRootView() }
}

/// File-scope (rather than nested inside ``StubHostingController``) so it
/// stays at one level of nesting depth.
private struct StubRootView {}

/// Plain `UIViewController` subclass with a stable type name for assertion.
private final class StubLeakingViewController: UIViewController {}

// MARK: - Tests

@available(iOS 16.0, *)
final class OTelInstrumenterAttributeProviderTests: XCTestCase {

    // MARK: - Test setup helpers

    private func makeInstrumenter(
        provider: MockTracerProvider,
        loggerProvider: MockLoggerProvider? = nil,
        attributeProvider: OTelAttributeProvider? = nil,
        now: Date = Date(timeIntervalSince1970: 1_700_000_000)
    ) -> OTelInstrumenter<TestScreen, TestFragment> {
        OTelInstrumenter<TestScreen, TestFragment>(
            screenIdentifier: nil,
            tracerProvider: provider,
            loggerProvider: loggerProvider,
            instrumentationName: "perfsuite-ios",
            instrumentationVersion: "1.7.0",
            attributeProvider: attributeProvider,
            now: { now }
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

    // MARK: - Attribute provider routing per signal kind

    func testStartupSpanInvokesAttributeProviderWithStartupContext() throws {
        let provider = MockTracerProvider()
        let spy = AttributeProviderSpy()
        let instrumenter = makeInstrumenter(provider: provider, attributeProvider: spy.makeProvider())

        let context = instrumenter.startupMeasurementStarted()
        instrumenter.startupMeasurementEnded(startupData(prewarmed: false), context: context)

        XCTAssertEqual(spy.captures.map(\.kind), [.startup])
    }

    func testScreenTTISpanInvokesAttributeProviderWithScreenContext() {
        let provider = MockTracerProvider()
        let spy = AttributeProviderSpy()
        let instrumenter = makeInstrumenter(provider: provider, attributeProvider: spy.makeProvider())

        _ = instrumenter.screenTTIMeasurementStarted(screen: .searchResults)

        XCTAssertEqual(spy.captures.count, 1)
        XCTAssertEqual(spy.captures.first?.kind, .screenTTI)
        XCTAssertEqual(spy.captures.first?.screenName, "search_results")
    }

    func testFragmentTTISpanInvokesAttributeProviderWithFragmentContext() {
        let provider = MockTracerProvider()
        let spy = AttributeProviderSpy()
        let instrumenter = makeInstrumenter(provider: provider, attributeProvider: spy.makeProvider())

        _ = instrumenter.fragmentTTIMeasurementStarted(fragment: .header)

        XCTAssertEqual(spy.captures.count, 1)
        XCTAssertEqual(spy.captures.first?.kind, .fragmentTTI)
        XCTAssertEqual(spy.captures.first?.fragmentName, "header")
    }

    func testScreenRenderingSpanInvokesAttributeProviderWithScreenContext() {
        let provider = MockTracerProvider()
        let spy = AttributeProviderSpy()
        let instrumenter = makeInstrumenter(provider: provider, attributeProvider: spy.makeProvider())

        _ = instrumenter.screenRenderingStarted(
            screen: .homescreen,
            sessionStarted: Date(timeIntervalSince1970: 1_700_000_000)
        )

        XCTAssertEqual(spy.captures.count, 1)
        XCTAssertEqual(spy.captures.first?.kind, .screenRendering)
        XCTAssertEqual(spy.captures.first?.screenName, "homescreen")
    }

    func testAppRenderingSpanInvokesAttributeProviderWithAppRenderingContext() {
        let provider = MockTracerProvider()
        let spy = AttributeProviderSpy()
        let instrumenter = makeInstrumenter(provider: provider, attributeProvider: spy.makeProvider())

        instrumenter.appRenderingSessionStarted(at: Date(timeIntervalSince1970: 1_700_000_000))
        instrumenter.appRenderingMetricsReceived(metrics: renderingMetrics())
        instrumenter.appRenderingSessionEnded()

        XCTAssertEqual(spy.captures.map(\.kind), [.appRendering])
    }

    /// Critical correctness lock: the receiver must construct
    /// `.fatalHang(info)`, *not* `.nonFatalHang`. Splitting the cases at
    /// construction time turns mis-threaded fatality into a compile-time
    /// error for any future maintainer.
    func testFatalHangReceiverConstructsFatalHangCase() throws {
        let provider = MockTracerProvider()
        let spy = AttributeProviderSpy()
        let instrumenter = makeInstrumenter(provider: provider, attributeProvider: spy.makeProvider())
        let info = HangInfo.with(callStack: "stack", duringStartup: false, duration: .milliseconds(2_500))

        instrumenter.fatalHangReceived(info: info)

        XCTAssertEqual(spy.captures.count, 1)
        XCTAssertEqual(spy.captures.first?.kind, .fatalHang)
        XCTAssertEqual(spy.captures.first?.hangFatality, .fatal)
    }

    /// Symmetric correctness lock for non-fatal hangs.
    func testNonFatalHangReceiverConstructsNonFatalHangCase() throws {
        let provider = MockTracerProvider()
        let spy = AttributeProviderSpy()
        let instrumenter = makeInstrumenter(provider: provider, attributeProvider: spy.makeProvider())
        let info = HangInfo.with(callStack: "stack", duringStartup: true, duration: .milliseconds(2_100))

        // Live hang: hangStarted opens the span; nonFatalHangReceived finalises it and runs the
        // attribute provider against the `.nonFatalHang` context.
        instrumenter.hangStarted(info: info)
        instrumenter.nonFatalHangReceived(info: info)

        XCTAssertEqual(spy.captures.count, 1)
        XCTAssertEqual(spy.captures.first?.kind, .nonFatalHang)
        XCTAssertEqual(spy.captures.first?.hangFatality, .nonFatal)
    }

    func testWatchdogTerminationSpanInvokesAttributeProviderWithWatchdogContext() {
        let provider = MockTracerProvider()
        let spy = AttributeProviderSpy()
        let instrumenter = makeInstrumenter(provider: provider, attributeProvider: spy.makeProvider())
        let data = WatchdogTerminationData(
            applicationState: .active,
            appStartInfo: .empty,
            duringStartup: false,
            memoryWarnings: 4
        )

        instrumenter.watchdogTerminationReceived(data)

        XCTAssertEqual(spy.captures.map(\.kind), [.watchdogTermination])
    }

    func testHostAttributesAppearOnEmittedSpan() throws {
        let provider = MockTracerProvider()
        let spy = AttributeProviderSpy()
        spy.attributesToReturn = ["EXPS0": .string("a"), "EXPS1": .string("b")]
        let instrumenter = makeInstrumenter(provider: provider, attributeProvider: spy.makeProvider())

        instrumenter.appRenderingSessionStarted(at: Date(timeIntervalSince1970: 1_700_000_000))
        instrumenter.appRenderingMetricsReceived(metrics: renderingMetrics())
        instrumenter.appRenderingSessionEnded()

        // Phase 4 live-span shape: app-rendering host attributes are merged at
        // finalize time and applied via `setAttribute` on the started span (not
        // on the spanBuilder, since the span is already running by then).
        let span = try XCTUnwrap(provider.tracer.lastBuilder?.startedSpan)
        XCTAssertEqual(span.attributes["EXPS0"]?.stringValue, "a")
        XCTAssertEqual(span.attributes["EXPS1"]?.stringValue, "b")
        XCTAssertEqual(span.attributes["rendering.total_frames"]?.intValue, 240)
    }

    func testHostAttributesCannotOverwriteSDKKeysOnEmittedSpan() throws {
        let provider = MockTracerProvider()
        let spy = AttributeProviderSpy()
        spy.attributesToReturn = [
            "rendering.total_frames": .int(99_999),
            "rendering.session_duration.ms": .int(1),
            "EXPS0": .string("ok"),
        ]
        let instrumenter = makeInstrumenter(provider: provider, attributeProvider: spy.makeProvider())

        instrumenter.appRenderingSessionStarted(at: Date(timeIntervalSince1970: 1_700_000_000))
        instrumenter.appRenderingMetricsReceived(metrics: renderingMetrics(sessionMs: 4_000))
        instrumenter.appRenderingSessionEnded()

        let span = try XCTUnwrap(provider.tracer.lastBuilder?.startedSpan)
        XCTAssertEqual(
            span.attributes["rendering.total_frames"]?.intValue, 240,
            "Host must not be able to overwrite an SDK-reserved attribute"
        )
        XCTAssertEqual(
            span.attributes["rendering.session_duration.ms"]?.intValue, 4_000,
            "Host must not be able to overwrite an SDK-reserved attribute"
        )
        XCTAssertEqual(
            span.attributes["EXPS0"]?.stringValue, "ok",
            "Non-reserved host attribute still passes through"
        )
    }

    func testAttributeProviderIsInvokedOncePerEmissionAcrossMultipleSignals() {
        let provider = MockTracerProvider()
        let spy = AttributeProviderSpy()
        let instrumenter = makeInstrumenter(provider: provider, attributeProvider: spy.makeProvider())

        let startupContext = instrumenter.startupMeasurementStarted()
        instrumenter.startupMeasurementEnded(startupData(prewarmed: false), context: startupContext)
        instrumenter.appRenderingSessionStarted(at: Date(timeIntervalSince1970: 1_700_000_000))
        instrumenter.appRenderingMetricsReceived(metrics: renderingMetrics())
        instrumenter.appRenderingSessionEnded()
        _ = instrumenter.screenTTIMeasurementStarted(screen: .homescreen)

        XCTAssertEqual(spy.captures.map(\.kind), [.startup, .appRendering, .screenTTI])
    }

    // MARK: - View-controller leak (log record)

    func testViewControllerLeakEmitsWarnLogWithExpectedAttributes() throws {
        let tracerProvider = MockTracerProvider()
        let loggerProvider = MockLoggerProvider()
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let instrumenter = makeInstrumenter(
            provider: tracerProvider,
            loggerProvider: loggerProvider,
            now: now
        )

        let viewController = StubLeakingViewController()
        instrumenter.viewControllerLeakReceived(viewController: viewController)

        XCTAssertEqual(loggerProvider.getCalls, ["perfsuite-ios"],
                       "Logger must be resolved with the instrumentation scope name")
        let builder = try XCTUnwrap(loggerProvider.logger.lastBuilder, "Expected one log record emitted")
        XCTAssertEqual(builder.severity, .warn)
        XCTAssertEqual(builder.body, .string("view_controller_leak"))
        XCTAssertEqual(builder.timestamp, now)
        XCTAssertEqual(builder.observedTimestamp, now)
        XCTAssertTrue(builder.emitted, "emit() must be called on the builder")

        XCTAssertEqual(builder.attributes["vc.class_name"]?.stringValue, "StubLeakingViewController")
        XCTAssertNotNil(builder.attributes["vc.identifier"]?.stringValue,
                        "Identifier defaults to the view controller's description")
        XCTAssertNotNil(builder.attributes["app.startup.prewarmed"]?.boolValue)
    }

    func testLeakLogUsesIntrospectedRootViewForClassName() throws {
        let tracerProvider = MockTracerProvider()
        let loggerProvider = MockLoggerProvider()
        let instrumenter = makeInstrumenter(
            provider: tracerProvider,
            loggerProvider: loggerProvider
        )

        instrumenter.viewControllerLeakReceived(viewController: StubHostingController())

        let builder = try XCTUnwrap(loggerProvider.logger.lastBuilder)
        XCTAssertEqual(
            builder.attributes["vc.class_name"]?.stringValue, "StubRootView",
            "When the VC conforms to RootViewIntrospectable, the refined root-view type must drive vc.class_name"
        )
    }

    func testLeakLogPlainViewControllerUsesConcreteSwiftType() throws {
        let tracerProvider = MockTracerProvider()
        let loggerProvider = MockLoggerProvider()
        let instrumenter = makeInstrumenter(
            provider: tracerProvider,
            loggerProvider: loggerProvider
        )

        instrumenter.viewControllerLeakReceived(viewController: StubLeakingViewController())

        let builder = try XCTUnwrap(loggerProvider.logger.lastBuilder)
        XCTAssertEqual(
            builder.attributes["vc.class_name"]?.stringValue, "StubLeakingViewController",
            "Non-introspectable VCs use the Swift type name verbatim"
        )
    }

    func testLeakLogInvokesAttributeProviderWithViewControllerLeakContext() throws {
        let tracerProvider = MockTracerProvider()
        let loggerProvider = MockLoggerProvider()
        let spy = AttributeProviderSpy()
        let viewController = StubLeakingViewController()
        let instrumenter = makeInstrumenter(
            provider: tracerProvider,
            loggerProvider: loggerProvider,
            attributeProvider: spy.makeProvider()
        )

        instrumenter.viewControllerLeakReceived(viewController: viewController)

        XCTAssertEqual(spy.captures.count, 1)
        XCTAssertEqual(spy.captures.first?.kind, .viewControllerLeak)
        XCTAssertTrue(
            spy.captures.first?.leakedViewController === viewController,
            "Provider must receive the exact VC instance via the .viewControllerLeak case"
        )
    }

    func testLeakLogMergesHostAttributesAndProtectsSDKKeys() throws {
        let tracerProvider = MockTracerProvider()
        let loggerProvider = MockLoggerProvider()
        let spy = AttributeProviderSpy()
        spy.attributesToReturn = [
            "EXPS0": .string("variant_a"),
            "vc.class_name": .string("HostOverride"),
            "app.startup.prewarmed": .bool(true),
        ]
        let instrumenter = makeInstrumenter(
            provider: tracerProvider,
            loggerProvider: loggerProvider,
            attributeProvider: spy.makeProvider()
        )

        instrumenter.viewControllerLeakReceived(viewController: StubLeakingViewController())

        let builder = try XCTUnwrap(loggerProvider.logger.lastBuilder)
        XCTAssertEqual(builder.attributes["EXPS0"]?.stringValue, "variant_a")
        XCTAssertEqual(
            builder.attributes["vc.class_name"]?.stringValue, "StubLeakingViewController",
            "Host must not be able to overwrite an SDK-reserved attribute"
        )
    }

    func testLoggerProviderResolutionIsLazyAcrossEmissions() {
        let tracerProvider = MockTracerProvider()
        let loggerProvider = MockLoggerProvider()
        let instrumenter = makeInstrumenter(
            provider: tracerProvider,
            loggerProvider: loggerProvider
        )

        instrumenter.viewControllerLeakReceived(viewController: StubLeakingViewController())
        instrumenter.viewControllerLeakReceived(viewController: StubLeakingViewController())

        XCTAssertEqual(loggerProvider.getCalls, ["perfsuite-ios", "perfsuite-ios"],
                       "Each emit should resolve the provider, not cache the logger at init time")
        XCTAssertEqual(loggerProvider.logger.builders.count, 2,
                       "Each leak should produce its own LogRecordBuilder")
    }

    func testInstrumenterShouldTrackDefaultsToTrue() {
        let tracerProvider = MockTracerProvider()
        let instrumenter: ViewControllerLeaksReceiver = makeInstrumenter(provider: tracerProvider)

        XCTAssertTrue(instrumenter.shouldTrack(viewController: UIViewController()))
        XCTAssertTrue(instrumenter.shouldTrack(viewController: UINavigationController()))
    }
}
