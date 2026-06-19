//
//  OTelInstrumenterShouldEmitTests.swift
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

/// Covers the `shouldEmit` gate on ``OTelInstrumenter``. Returning `false`
/// from the closure short-circuits the corresponding span (or log record)
/// emission before any provider attribute is evaluated or any tracer / logger
/// is resolved.
@available(iOS 16.0, *)
final class OTelInstrumenterShouldEmitTests: XCTestCase {

    private enum TestScreen: String {
        case homescreen
    }

    private enum TestFragment: Equatable {
        case header
    }

    private let pinnedNow = Date(timeIntervalSince1970: 1_700_000_000)

    private func makeInstrumenter(
        provider: MockTracerProvider,
        loggerProvider: MockLoggerProvider? = nil,
        shouldEmit: ((PerformanceSuiteSignalContext) -> Bool)? = nil
    ) -> OTelInstrumenter<TestScreen, TestFragment> {
        OTelInstrumenter<TestScreen, TestFragment>(
            screenIdentifier: nil,
            tracerProvider: provider,
            loggerProvider: loggerProvider,
            instrumentationName: "perfsuite-ios",
            instrumentationVersion: "1.9.0",
            shouldEmit: shouldEmit,
            now: { self.pinnedNow }
        )
    }

    private func startupData(prewarmed: Bool) -> StartupTimeData {
        StartupTimeData(
            totalTime: .milliseconds(1_500),
            preMainTime: .milliseconds(200),
            mainTime: .milliseconds(1_300),
            totalBeforeViewControllerTime: .milliseconds(1_400),
            mainBeforeViewControllerTime: .milliseconds(1_200),
            appStartInfo: AppStartInfo(appStartedWithPrewarming: prewarmed)
        )
    }

    private func hangInfo() -> HangInfo {
        HangInfo.with(callStack: "stack", duringStartup: false, duration: .milliseconds(2_500))
    }

    // MARK: - Suppression of span emissions

    func testShouldEmitCanReadStartupPayloadAndDropPrewarmedLaunches() throws {
        let provider = MockTracerProvider()
        let instrumenter = makeInstrumenter(
            provider: provider,
            shouldEmit: { context in
                if case .startup(let data) = context {
                    return !data.appStartInfo.appStartedWithPrewarming
                }
                return true
            }
        )

        // Live startup opens a raw span at start; shouldEmit reads the payload at finalize. A
        // prewarmed launch ends with Status.error; a non-prewarmed one carries finalize attributes.
        let prewarmed = instrumenter.startupMeasurementStarted()
        instrumenter.startupMeasurementEnded(startupData(prewarmed: true), context: prewarmed)
        let prewarmedSpan = try XCTUnwrap(provider.tracer.lastBuilder?.startedSpan)
        guard case .error = prewarmedSpan.status else {
            return XCTFail("Prewarmed launch must be rejected by shouldEmit, got \(prewarmedSpan.status)")
        }

        let normal = instrumenter.startupMeasurementStarted()
        instrumenter.startupMeasurementEnded(startupData(prewarmed: false), context: normal)
        let normalSpan = try XCTUnwrap(provider.tracer.lastBuilder?.startedSpan)
        XCTAssertEqual(normalSpan.attributes["app.startup.total_time.ms"]?.intValue, 1_500,
                       "Accepted launch carries finalize attributes")
    }

    func testShouldEmitRejectionOnLiveStartupSpanEndsWithRejectedStatus() throws {
        // Rejected live spans are ended with Status.error rather than never opened, so downstream can filter them.
        let provider = MockTracerProvider()
        let instrumenter = makeInstrumenter(
            provider: provider,
            shouldEmit: { context in
                if case .startup = context { return false }
                return true
            }
        )

        let context = instrumenter.startupMeasurementStarted()
        XCTAssertEqual(provider.tracer.builders.count, 1, "Raw live span opens before the gate runs")
        instrumenter.startupMeasurementEnded(startupData(prewarmed: false), context: context)

        let span = try XCTUnwrap(provider.tracer.lastBuilder?.startedSpan)
        XCTAssertTrue(span.ended)
        guard case let .error(description) = span.status else {
            return XCTFail("Rejected live span must end with Status.error, got \(span.status)")
        }
        XCTAssertEqual(description, "shouldEmit_rejected")
        XCTAssertNil(span.attributes["app.startup.total_time.ms"],
                     "Rejected span carries no finalize attributes")
    }

    func testShouldEmitNotEvaluatedForOtherSignalsWhenFilteringStartup() throws {
        let provider = MockTracerProvider()
        let instrumenter = makeInstrumenter(
            provider: provider,
            shouldEmit: { context in
                if case .startup = context { return false }
                return true
            }
        )

        // A shouldEmit closure that rejects only `.startup` must not suppress the fatal-hang span.
        instrumenter.fatalHangReceived(info: hangInfo())

        XCTAssertEqual(provider.tracer.builders.count, 1)
        XCTAssertEqual(provider.tracer.lastBuilder?.spanName, "app-hang")
    }

    // MARK: - Suppression of log emissions

    func testShouldEmitFalseSuppressesViewControllerLeakLog() throws {
        let provider = MockTracerProvider()
        let loggerProvider = MockLoggerProvider()
        let instrumenter = makeInstrumenter(
            provider: provider,
            loggerProvider: loggerProvider,
            shouldEmit: { context in
                if case .viewControllerLeak = context { return false }
                return true
            }
        )

        instrumenter.viewControllerLeakReceived(viewController: UIViewController())

        XCTAssertTrue(loggerProvider.logger.builders.isEmpty,
                      "shouldEmit returning false on .viewControllerLeak must suppress log emission")
    }

    // MARK: - Default behaviour when shouldEmit is absent

    func testAbsentShouldEmitEmitsEverySignal() throws {
        let provider = MockTracerProvider()
        let instrumenter = makeInstrumenter(provider: provider)

        let context = instrumenter.startupMeasurementStarted()
        instrumenter.startupMeasurementEnded(startupData(prewarmed: true), context: context)

        XCTAssertEqual(provider.tracer.builders.count, 1,
                       "Without shouldEmit, every emission flows through — including prewarmed startups")
        let span = try XCTUnwrap(provider.tracer.lastBuilder?.startedSpan)
        XCTAssertEqual(span.attributes["app.startup.prewarmed"]?.boolValue, true)
    }
}
