//
//  PerformanceSuiteSignalContextTests.swift
//  PerformanceSuiteOTel-Tests
//
//  Created by Ahmed Nafei on 18/05/2026.
//

import OpenTelemetryApi
@testable import PerformanceSuite
import UIKit
import XCTest

#if canImport(PerformanceSuiteOTel)
@testable import PerformanceSuiteOTel
#endif

/// Surface-lock tests for the public ``PerformanceSuiteSignalContext`` enum,
/// its projection structs, and ``PerformanceSuiteSignalKind``. These tests
/// pin the public API so any accidental rename / removal trips a build error
/// at the test target rather than silently breaking host enrichment closures.
final class PerformanceSuiteSignalContextTests: XCTestCase {

    func testKindAccessorReturnsExpectedValueForEveryCase() {
        let hangInfo = HangInfo.with(callStack: "stack", duringStartup: false, duration: .milliseconds(500))
        let watchdog = WatchdogTerminationData(
            applicationState: .active,
            appStartInfo: .empty,
            duringStartup: false,
            memoryWarnings: 0
        )
        let viewController = UIViewController()

        let cases: [(PerformanceSuiteSignalContext, PerformanceSuiteSignalKind)] = [
            (.startup(StartupContext()), .startup),
            (.screenTTI(ScreenContext(screenName: "home")), .screenTTI),
            (.fragmentTTI(FragmentContext(fragmentName: "header")), .fragmentTTI),
            (.screenRendering(ScreenContext(screenName: "home")), .screenRendering),
            (.appRendering(AppRenderingContext()), .appRendering),
            (.fatalHang(hangInfo), .fatalHang),
            (.nonFatalHang(hangInfo), .nonFatalHang),
            (.watchdogTermination(watchdog), .watchdogTermination),
            (.viewControllerLeak(viewController), .viewControllerLeak),
        ]

        XCTAssertEqual(cases.count, PerformanceSuiteSignalKind.allCases.count,
                       "Every PerformanceSuiteSignalKind must be represented above; otherwise the kind-accessor coverage is incomplete")
        for (context, expectedKind) in cases {
            XCTAssertEqual(context.kind, expectedKind)
        }
    }

    func testSignalKindRawValuesAreStable() {
        // Backends and dashboards key off these raw values; renaming a case
        // would silently break filters in production. Pin them here.
        XCTAssertEqual(PerformanceSuiteSignalKind.startup.rawValue, "startup")
        XCTAssertEqual(PerformanceSuiteSignalKind.screenTTI.rawValue, "screenTTI")
        XCTAssertEqual(PerformanceSuiteSignalKind.fragmentTTI.rawValue, "fragmentTTI")
        XCTAssertEqual(PerformanceSuiteSignalKind.screenRendering.rawValue, "screenRendering")
        XCTAssertEqual(PerformanceSuiteSignalKind.appRendering.rawValue, "appRendering")
        XCTAssertEqual(PerformanceSuiteSignalKind.fatalHang.rawValue, "fatalHang")
        XCTAssertEqual(PerformanceSuiteSignalKind.nonFatalHang.rawValue, "nonFatalHang")
        XCTAssertEqual(PerformanceSuiteSignalKind.watchdogTermination.rawValue, "watchdogTermination")
        XCTAssertEqual(PerformanceSuiteSignalKind.viewControllerLeak.rawValue, "viewControllerLeak")
    }

    func testProjectionStructsAreEquatable() {
        XCTAssertEqual(StartupContext(), StartupContext())
        XCTAssertEqual(AppRenderingContext(), AppRenderingContext())
        XCTAssertEqual(ScreenContext(screenName: "home"), ScreenContext(screenName: "home"))
        XCTAssertNotEqual(ScreenContext(screenName: "home"), ScreenContext(screenName: "search"))
        XCTAssertEqual(FragmentContext(fragmentName: "header"), FragmentContext(fragmentName: "header"))
        XCTAssertNotEqual(FragmentContext(fragmentName: "header"), FragmentContext(fragmentName: "footer"))
    }

    func testScreenContextScreenNameIsNonOptional() {
        // Compile-time check expressed as a runtime fixture: the projection
        // exposes `screenName: String` (not `String?`), reflecting that the
        // emitter always supplies a non-nil identifier at construction.
        let context = ScreenContext(screenName: "search_results")
        XCTAssertEqual(context.screenName, "search_results")
    }

    func testFragmentContextHasNoScreenName() {
        // FragmentContext intentionally exposes only `fragmentName` because
        // perfsuite-ios fragments are screen-independent at the SDK level.
        // Hosts that track screen-fragment correlation populate it through
        // the OTelAttributeProvider's returned dictionary.
        let context = FragmentContext(fragmentName: "header")
        XCTAssertEqual(context.fragmentName, "header")
    }

    func testHangInfoIsForwardedVerbatimThroughTheEnum() {
        let info = HangInfo.with(callStack: "stack", duringStartup: true, duration: .milliseconds(2_500))

        let fatal: PerformanceSuiteSignalContext = .fatalHang(info)
        let nonFatal: PerformanceSuiteSignalContext = .nonFatalHang(info)

        if case .fatalHang(let bound) = fatal {
            XCTAssertEqual(bound.duringStartup, info.duringStartup)
            XCTAssertEqual(bound.duration.milliseconds, info.duration.milliseconds)
        } else {
            XCTFail("Expected .fatalHang case to bind the supplied HangInfo")
        }

        if case .nonFatalHang(let bound) = nonFatal {
            XCTAssertEqual(bound.duringStartup, info.duringStartup)
        } else {
            XCTFail("Expected .nonFatalHang case to bind the supplied HangInfo")
        }
    }
}
