//
//  OTelSpanNamePrefixTests.swift
//  PerformanceSuiteOTel-Tests
//
//  Created by Ahmed Nafei on 01/05/2026.
//

import OpenTelemetryApi
@testable import PerformanceSuite
import UIKit
import XCTest

#if canImport(PerformanceSuiteOTel)
@testable import PerformanceSuiteOTel
#endif

private enum TestScreen: String {
    case homescreen
    case searchResults = "search_results"
}

private enum TestFragment: Equatable {
    case header
}

final class OTelSpanNamePrefixTests: XCTestCase {

    private func makePrefixedInstrumenter(
        provider: MockTracerProvider,
        prefix: String?
    ) -> OTelInstrumenter<TestScreen, TestFragment> {
        OTelInstrumenter<TestScreen, TestFragment>(
            screenIdentifier: nil,
            tracerProvider: provider,
            instrumentationName: "perfsuite-ios",
            instrumentationVersion: "1.7.0",
            spanNamePrefix: prefix,
            now: { Date(timeIntervalSince1970: 1_700_000_000) }
        )
    }

    func testPrefixIsAppliedToAllSpanTypes() throws {
        let provider = MockTracerProvider()
        let instrumenter = makePrefixedInstrumenter(provider: provider, prefix: "bookingcom")

        let startup = StartupTimeData(
            totalTime: .milliseconds(1_500), preMainTime: .milliseconds(300),
            mainTime: .milliseconds(1_200), totalBeforeViewControllerTime: .milliseconds(900),
            mainBeforeViewControllerTime: .milliseconds(600),
            appStartInfo: AppStartInfo(appStartedWithPrewarming: false)
        )
        instrumenter.startupTimeReceived(startup)
        XCTAssertEqual(provider.tracer.builders.last?.spanName, "bookingcom.app-startup")

        let tti = TTIMetrics(tti: .milliseconds(800), ttfr: .milliseconds(50), appStartInfo: .empty)
        instrumenter.ttiMetricsReceived(metrics: tti, screen: .searchResults)
        XCTAssertEqual(provider.tracer.builders.last?.spanName, "bookingcom.screen-tti.search_results")

        instrumenter.fragmentTTIMetricsReceived(metrics: tti, fragment: .header)
        XCTAssertEqual(provider.tracer.builders.last?.spanName, "bookingcom.fragment-tti.header")

        let rendering = RenderingMetrics(
            renderedFrames: 240, expectedFrames: 240, droppedFrames: 5,
            frozenFrames: 0, slowFrames: 7, freezeTime: .milliseconds(120),
            sessionDuration: .milliseconds(4_000), appStartInfo: .empty
        )
        instrumenter.renderingMetricsReceived(metrics: rendering, screen: .homescreen)
        XCTAssertEqual(provider.tracer.builders.last?.spanName, "bookingcom.screen-rendering.homescreen")

        NotificationCenter.default.post(name: UIApplication.didBecomeActiveNotification, object: nil)
        instrumenter.appRenderingMetricsReceived(metrics: rendering)
        NotificationCenter.default.post(name: UIApplication.didEnterBackgroundNotification, object: nil)
        XCTAssertEqual(provider.tracer.builders.last?.spanName, "bookingcom.app-rendering")

        let hangInfo = HangInfo.with(callStack: "stack", duringStartup: false, duration: .milliseconds(2_500))
        instrumenter.fatalHangReceived(info: hangInfo)
        XCTAssertEqual(provider.tracer.builders.last?.spanName, "bookingcom.app-hang")

        let wtData = WatchdogTerminationData(
            applicationState: .active, appStartInfo: .empty,
            duringStartup: false, memoryWarnings: 1
        )
        instrumenter.watchdogTerminationReceived(wtData)
        XCTAssertEqual(provider.tracer.builders.last?.spanName, "bookingcom.app-watchdog-termination")
    }

    func testNilPrefixEmitsUnprefixedSpanNames() throws {
        let provider = MockTracerProvider()
        let instrumenter = makePrefixedInstrumenter(provider: provider, prefix: nil)

        let tti = TTIMetrics(tti: .milliseconds(800), ttfr: .milliseconds(50), appStartInfo: .empty)
        instrumenter.ttiMetricsReceived(metrics: tti, screen: .searchResults)

        let builder = try XCTUnwrap(provider.tracer.lastBuilder)
        XCTAssertEqual(builder.spanName, "screen-tti.search_results",
                       "nil prefix must not add a dot or empty segment")
    }
}
