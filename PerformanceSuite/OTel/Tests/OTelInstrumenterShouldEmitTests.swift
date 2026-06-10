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

        instrumenter.startupTimeReceived(startupData(prewarmed: true))
        XCTAssertTrue(provider.tracer.builders.isEmpty,
                      "Prewarmed startup is dropped by the host's shouldEmit closure")

        instrumenter.startupTimeReceived(startupData(prewarmed: false))
        XCTAssertEqual(provider.tracer.builders.count, 1,
                       "Non-prewarmed startup reaches the OTel pipeline")
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

        instrumenter.startupTimeReceived(startupData(prewarmed: false))    // suppressed
        instrumenter.fatalHangReceived(info: hangInfo())                   // emitted

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

        instrumenter.startupTimeReceived(startupData(prewarmed: true))

        XCTAssertEqual(provider.tracer.builders.count, 1,
                       "Without shouldEmit, every emission flows through — including prewarmed startups")
        XCTAssertEqual(provider.tracer.lastBuilder?.attributes["app.startup.prewarmed"]?.boolValue, true)
    }
}
