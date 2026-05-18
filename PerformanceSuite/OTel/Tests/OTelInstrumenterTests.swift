//
//  OTelInstrumenterTests.swift
//  PerformanceSuiteOTel-Tests
//
//  Created by Ahmed Nafei on 30/04/2026.
//

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

final class OTelInstrumenterTests: XCTestCase {

    // MARK: - Test setup helpers

    /// Build an instrumenter that uses the supplied `MockTracerProvider` and a
    /// fixed `now` clock so we can verify `start = end - duration` exactly,
    /// without flakiness from real time passing during the test.
    private func makeInstrumenter(
        provider: MockTracerProvider,
        attributeProvider: OTelAttributeProvider? = nil,
        now: Date = Date(timeIntervalSince1970: 1_700_000_000)
    ) -> OTelInstrumenter<TestScreen, TestFragment> {
        OTelInstrumenter<TestScreen, TestFragment>(
            screenIdentifier: nil,
            tracerProvider: provider,
            instrumentationName: "perfsuite-ios",
            instrumentationVersion: "1.7.0",
            attributeProvider: attributeProvider,
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

    // MARK: - Startup

    func testStartupSpanEmittedWithExpectedNameAndAttributes() throws {
        let provider = MockTracerProvider()
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let instrumenter = makeInstrumenter(provider: provider, now: now)

        instrumenter.startupTimeReceived(startupData(prewarmed: false))

        let builder = try XCTUnwrap(provider.tracer.lastBuilder, "Expected one span emitted")
        XCTAssertEqual(builder.spanName, "app-startup")
        XCTAssertEqual(builder.spanKind, .internal)
        XCTAssertEqual(builder.parentMode, .noParent)

        XCTAssertEqual(builder.attributes["app.startup.total_time.ms"]?.intValue, 1_500)
        XCTAssertEqual(builder.attributes["app.startup.main_time.ms"]?.intValue, 1_200)
        XCTAssertEqual(builder.attributes["app.startup.premain_time.ms"]?.intValue, 300)
        XCTAssertEqual(builder.attributes["app.startup.prewarmed"]?.boolValue, false)
        XCTAssertEqual(builder.attributes["os.name"]?.stringValue, "iOS")
        XCTAssertNotNil(builder.attributes["device.model"]?.stringValue)
        XCTAssertNotNil(builder.attributes["os.version"]?.stringValue)

        let span = try XCTUnwrap(builder.startedSpan)
        XCTAssertTrue(span.ended, "Span must be ended after emission")
        XCTAssertEqual(span.firstEndTime, now)
        let startTime = try XCTUnwrap(builder.startTime)
        XCTAssertEqual(startTime.timeIntervalSince1970,
                       now.addingTimeInterval(-1.5).timeIntervalSince1970,
                       accuracy: 0.001,
                       "startTime must be (now - totalTime)")
    }

    func testStartupSpanIncludesPrewarmedTrueAttribute() throws {
        let provider = MockTracerProvider()
        let instrumenter = makeInstrumenter(provider: provider)

        instrumenter.startupTimeReceived(startupData(prewarmed: true))

        let builder = try XCTUnwrap(provider.tracer.lastBuilder)
        XCTAssertEqual(
            builder.attributes["app.startup.prewarmed"]?.boolValue, true,
            "OTel side always emits, including for prewarmed launches"
        )
    }

    // MARK: - Screen TTI

    func testScreenTTISpanEmittedWithRawValueInName() throws {
        let provider = MockTracerProvider()
        let instrumenter = makeInstrumenter(provider: provider)

        instrumenter.ttiMetricsReceived(metrics: metrics(tti: 800), screen: .searchResults)

        let builder = try XCTUnwrap(provider.tracer.lastBuilder)
        XCTAssertEqual(builder.spanName, "screen-tti.search_results",
                       "Screen identifier must be the rawValue, not the Swift case name")
        XCTAssertEqual(builder.spanKind, .internal)
        XCTAssertEqual(builder.parentMode, .noParent)
        XCTAssertEqual(builder.attributes["screen.name"]?.stringValue, "search_results")
        XCTAssertEqual(builder.attributes["screen.tti.ms"]?.intValue, 800)
        XCTAssertEqual(builder.attributes["screen.ttfr.ms"]?.intValue, 50)

        let span = try XCTUnwrap(builder.startedSpan)
        XCTAssertTrue(span.ended)
    }

    // MARK: - Fragment TTI

    func testFragmentTTISpanUsesStringDescribingFallbackForNonRawRepresentable() throws {
        let provider = MockTracerProvider()
        let instrumenter = makeInstrumenter(provider: provider)

        instrumenter.fragmentTTIMetricsReceived(metrics: metrics(tti: 250), fragment: .header)

        let builder = try XCTUnwrap(provider.tracer.lastBuilder)
        XCTAssertEqual(builder.spanName, "fragment-tti.header",
                       "Fallback to String(describing:) for non-String-backed RawRepresentable types")
        XCTAssertEqual(builder.attributes["fragment.name"]?.stringValue, "header")
        XCTAssertEqual(builder.attributes["fragment.tti.ms"]?.intValue, 250)
        XCTAssertEqual(builder.attributes["fragment.ttfr.ms"]?.intValue, 50)
    }

    // MARK: - Screen rendering

    func testScreenRenderingSpanCarriesRenderingAttributes() throws {
        let provider = MockTracerProvider()
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let instrumenter = makeInstrumenter(provider: provider, now: now)

        instrumenter.renderingMetricsReceived(metrics: renderingMetrics(), screen: .homescreen)

        let builder = try XCTUnwrap(provider.tracer.lastBuilder)
        XCTAssertEqual(builder.spanName, "screen-rendering.homescreen")
        XCTAssertEqual(builder.attributes["screen.name"]?.stringValue, "homescreen")
        XCTAssertEqual(builder.attributes["rendering.total_frames"]?.intValue, 240)
        XCTAssertEqual(builder.attributes["rendering.dropped_frames"]?.intValue, 5)
        XCTAssertEqual(builder.attributes["rendering.slow_frames"]?.intValue, 7)
        XCTAssertEqual(builder.attributes["rendering.freeze_time.ms"]?.intValue, 120)
        XCTAssertEqual(builder.attributes["rendering.session_duration.ms"]?.intValue, 4_000)

        let startTime = try XCTUnwrap(builder.startTime)
        XCTAssertEqual(startTime.timeIntervalSince1970,
                       now.addingTimeInterval(-4.0).timeIntervalSince1970,
                       accuracy: 0.001,
                       "Rendering span spans the session_duration ending now")
    }

    // MARK: - App rendering

    func testAppRenderingSpanIsScreenless() throws {
        let provider = MockTracerProvider()
        let instrumenter = makeInstrumenter(provider: provider)

        instrumenter.appRenderingMetricsReceived(metrics: renderingMetrics(sessionMs: 2_000))

        let builder = try XCTUnwrap(provider.tracer.lastBuilder)
        XCTAssertEqual(builder.spanName, "app-rendering")
        XCTAssertNil(builder.attributes["screen.name"])
        XCTAssertEqual(builder.attributes["rendering.session_duration.ms"]?.intValue, 2_000)
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

    func testNonFatalHangEmitsAppHangSpanWithNonFatalType() throws {
        let provider = MockTracerProvider()
        let instrumenter = makeInstrumenter(provider: provider)
        let info = HangInfo.with(callStack: "stack", duringStartup: true, duration: .milliseconds(2_100))

        instrumenter.nonFatalHangReceived(info: info)

        let builder = try XCTUnwrap(provider.tracer.lastBuilder)
        XCTAssertEqual(builder.spanName, "app-hang")
        XCTAssertEqual(builder.attributes["hang.type"]?.stringValue, "non_fatal")
        XCTAssertEqual(builder.attributes["hang.duration.ms"]?.intValue, 2_100)
        XCTAssertEqual(builder.attributes["hang.during_startup"]?.boolValue, true)
    }

    func testHangStartedDoesNotEmitAnySpan() {
        let provider = MockTracerProvider()
        let instrumenter = makeInstrumenter(provider: provider)
        let info = HangInfo.with(callStack: "stack", duringStartup: false, duration: .milliseconds(2_000))

        instrumenter.hangStarted(info: info)

        XCTAssertTrue(
            provider.tracer.builders.isEmpty,
            "hangStarted is an in-progress signal; no completed span is recorded for it"
        )
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
        XCTAssertEqual(builder.attributes["app.state"]?.stringValue, "active")
        XCTAssertEqual(builder.attributes["memory.warnings_count"]?.intValue, 4)
        XCTAssertNotNil(builder.attributes["device.ram.mb"]?.intValue)

        let span = try XCTUnwrap(builder.startedSpan)
        XCTAssertEqual(span.firstEndTime, builder.startTime,
                       "Watchdog termination is recorded as a zero-duration point in time")
    }

    // MARK: - Tracer provider resolution

    func testTracerProviderReceivesInstrumentationNameAndVersion() {
        let provider = MockTracerProvider()
        let instrumenter = makeInstrumenter(provider: provider)

        instrumenter.startupTimeReceived(startupData(prewarmed: false))

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

        instrumenter.startupTimeReceived(startupData(prewarmed: false))
        instrumenter.appRenderingMetricsReceived(metrics: renderingMetrics())

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

    // MARK: - Attribute provider routing per signal kind

    /// Captures every (kind, sample-fields) tuple the attribute provider
    /// receives, so each per-signal test can assert that its emission reached
    /// the provider with the right context shape.
    private final class AttributeProviderSpy {
        struct Capture {
            let kind: PerformanceSuiteSignalKind
            let screenName: String?
            let fragmentName: String?
            let hangFatality: HangFatality?
            let leakedViewController: UIViewController?
        }

        enum HangFatality { case fatal, nonFatal }

        private(set) var captures: [Capture] = []
        var attributesToReturn: [String: AttributeValue] = [:]

        func makeProvider() -> OTelAttributeProvider {
            { [weak self] context in
                guard let self else { return [:] }
                let screenName: String?
                let fragmentName: String?
                let hangFatality: HangFatality?
                let leakedViewController: UIViewController?
                switch context {
                case .startup, .appRendering:
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
                case .watchdogTermination:
                    screenName = nil; fragmentName = nil
                    hangFatality = nil; leakedViewController = nil
                case .viewControllerLeak(let viewController):
                    screenName = nil; fragmentName = nil
                    hangFatality = nil; leakedViewController = viewController
                }
                self.captures.append(Capture(
                    kind: context.kind,
                    screenName: screenName,
                    fragmentName: fragmentName,
                    hangFatality: hangFatality,
                    leakedViewController: leakedViewController
                ))
                return self.attributesToReturn
            }
        }
    }

    func testStartupSpanInvokesAttributeProviderWithStartupContext() throws {
        let provider = MockTracerProvider()
        let spy = AttributeProviderSpy()
        let instrumenter = makeInstrumenter(provider: provider, attributeProvider: spy.makeProvider())

        instrumenter.startupTimeReceived(startupData(prewarmed: false))

        XCTAssertEqual(spy.captures.map(\.kind), [.startup])
    }

    func testScreenTTISpanInvokesAttributeProviderWithScreenContext() {
        let provider = MockTracerProvider()
        let spy = AttributeProviderSpy()
        let instrumenter = makeInstrumenter(provider: provider, attributeProvider: spy.makeProvider())

        instrumenter.ttiMetricsReceived(metrics: metrics(tti: 800), screen: .searchResults)

        XCTAssertEqual(spy.captures.count, 1)
        XCTAssertEqual(spy.captures.first?.kind, .screenTTI)
        XCTAssertEqual(spy.captures.first?.screenName, "search_results")
    }

    func testFragmentTTISpanInvokesAttributeProviderWithFragmentContext() {
        let provider = MockTracerProvider()
        let spy = AttributeProviderSpy()
        let instrumenter = makeInstrumenter(provider: provider, attributeProvider: spy.makeProvider())

        instrumenter.fragmentTTIMetricsReceived(metrics: metrics(tti: 250), fragment: .header)

        XCTAssertEqual(spy.captures.count, 1)
        XCTAssertEqual(spy.captures.first?.kind, .fragmentTTI)
        XCTAssertEqual(spy.captures.first?.fragmentName, "header")
    }

    func testScreenRenderingSpanInvokesAttributeProviderWithScreenContext() {
        let provider = MockTracerProvider()
        let spy = AttributeProviderSpy()
        let instrumenter = makeInstrumenter(provider: provider, attributeProvider: spy.makeProvider())

        instrumenter.renderingMetricsReceived(metrics: renderingMetrics(), screen: .homescreen)

        XCTAssertEqual(spy.captures.count, 1)
        XCTAssertEqual(spy.captures.first?.kind, .screenRendering)
        XCTAssertEqual(spy.captures.first?.screenName, "homescreen")
    }

    func testAppRenderingSpanInvokesAttributeProviderWithAppRenderingContext() {
        let provider = MockTracerProvider()
        let spy = AttributeProviderSpy()
        let instrumenter = makeInstrumenter(provider: provider, attributeProvider: spy.makeProvider())

        instrumenter.appRenderingMetricsReceived(metrics: renderingMetrics())

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

        instrumenter.appRenderingMetricsReceived(metrics: renderingMetrics())

        let builder = try XCTUnwrap(provider.tracer.lastBuilder)
        XCTAssertEqual(builder.attributes["EXPS0"]?.stringValue, "a")
        XCTAssertEqual(builder.attributes["EXPS1"]?.stringValue, "b")
        // SDK-set rendering attributes still on the span:
        XCTAssertEqual(builder.attributes["rendering.total_frames"]?.intValue, 240)
    }

    /// Defense-in-depth integration test on top of `OTelAttributeMergeTests`:
    /// confirms that even when the host returns a key that the SDK is about
    /// to set on this same emission, the SDK value wins on the resulting
    /// span builder.
    func testHostAttributesCannotOverwriteSDKKeysOnEmittedSpan() throws {
        let provider = MockTracerProvider()
        let spy = AttributeProviderSpy()
        spy.attributesToReturn = [
            "rendering.total_frames": .int(99_999),
            "rendering.session_duration.ms": .int(1),
            "EXPS0": .string("ok"),
        ]
        let instrumenter = makeInstrumenter(provider: provider, attributeProvider: spy.makeProvider())

        instrumenter.appRenderingMetricsReceived(metrics: renderingMetrics(sessionMs: 4_000))

        let builder = try XCTUnwrap(provider.tracer.lastBuilder)
        XCTAssertEqual(
            builder.attributes["rendering.total_frames"]?.intValue, 240,
            "Host must not be able to overwrite an SDK-reserved attribute"
        )
        XCTAssertEqual(
            builder.attributes["rendering.session_duration.ms"]?.intValue, 4_000,
            "Host must not be able to overwrite an SDK-reserved attribute"
        )
        XCTAssertEqual(
            builder.attributes["EXPS0"]?.stringValue, "ok",
            "Non-reserved host attribute still passes through"
        )
    }

    func testAttributeProviderIsInvokedOncePerEmissionAcrossMultipleSignals() {
        let provider = MockTracerProvider()
        let spy = AttributeProviderSpy()
        let instrumenter = makeInstrumenter(provider: provider, attributeProvider: spy.makeProvider())

        instrumenter.startupTimeReceived(startupData(prewarmed: false))
        instrumenter.appRenderingMetricsReceived(metrics: renderingMetrics())
        instrumenter.ttiMetricsReceived(metrics: metrics(tti: 800), screen: .homescreen)

        XCTAssertEqual(spy.captures.map(\.kind), [.startup, .appRendering, .screenTTI])
    }
}
