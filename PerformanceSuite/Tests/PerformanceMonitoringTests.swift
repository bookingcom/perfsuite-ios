//
//  PerformanceMonitoringTests.swift
//  PerformanceSuite-Tests
//
//  Created by Gleb Tarasov on 25/09/2023.
//

import XCTest
@testable import PerformanceSuite

final class PerformanceMonitoringTests: XCTestCase {

    override func setUpWithError() throws {
        super.setUp()
        continueAfterFailure = false
        try PerformanceMonitoring.disable()
        StartupTimeReporter.forgetMainStartedForTests()
        AppInfoHolder.resetForTests()
    }

    override func tearDown() {
        super.tearDown()
        PerformanceMonitoring.queue.sync { }
        PerformanceMonitoring.consumerQueue.sync { }
        StartupTimeReporter.forgetMainStartedForTests()
    }

    func testIntegration() throws {
        PerformanceMonitoring.onMainStarted()
        try PerformanceMonitoring.enable(config: .all(receiver: self))

        let exp = expectation(description: "onInit")
        onInitExpectation = exp
        let vc = UIViewController()
        wait(for: [exp], timeout: 20) // increase timeout as it is very slow on CI
        _ = vc

        // simulate vc appearance to generate more performance events
        // checking there are no crashes
        _ = vc.view
        vc.beginAppearanceTransition(true, animated: false)
        vc.endAppearanceTransition()
        vc.beginAppearanceTransition(false, animated: false)
        vc.endAppearanceTransition()

        PerformanceMonitoring.queue.sync { }
        PerformanceMonitoring.consumerQueue.sync { }
        waitForTheNextRunLoop()

        try PerformanceMonitoring.disable()

        let exp2 = expectation(description: "onInit2")
        exp2.isInverted = true
        onInitExpectation = exp2
        let vc2 = UIViewController()
        wait(for: [exp2], timeout: 5)
        _ = vc2

        let appStartInfo = PerformanceMonitoring.appStartInfo
        XCTAssertFalse(appStartInfo.appStartedWithPrewarming)
    }

    func testPrewarming() throws {
        setenv("ActivePrewarm", "1", 1)
        PerformanceMonitoring.onMainStarted()
        try PerformanceMonitoring.enable(config: .all(receiver: self))

        XCTAssertTrue(PerformanceMonitoring.appStartInfo.appStartedWithPrewarming)

        try PerformanceMonitoring.disable()
        setenv("ActivePrewarm", "", 1)
    }

    func testNoPrewarming() throws {
        setenv("ActivePrewarm", "", 1)
        PerformanceMonitoring.onMainStarted()
        try PerformanceMonitoring.enable(config: .all(receiver: self))

        XCTAssertFalse(PerformanceMonitoring.appStartInfo.appStartedWithPrewarming)

        try PerformanceMonitoring.disable()
    }

    func testEnableWithCrashlytics() async throws {
        configureFirebase()
        let settings = CrashlyticsHangsSettings(reportingMode: .fatalHangsAsNonFatals,
                                                hangReason: "my_reason",
                                                hangTypeFormatter: customHangTypeFormatter)
        try PerformanceMonitoring.enableWithCrashlyticsSupport(config: .all(receiver: self), settings: settings)

        let hangReporter = try XCTUnwrap(PerformanceMonitoring.appReporters.compactMap { $0 as? HangReporter }.first)
        // check that hangsReceiver is properly wrapped
        XCTAssertTrue(hangReporter.receiver is CrashlyticsHangsReceiverWrapper)
        let wrapper = try XCTUnwrap(hangReporter.receiver as? CrashlyticsHangsReceiverWrapper)
        XCTAssertEqual(wrapper.hangsReceiver as? PerformanceMonitoringTests, self)
        XCTAssertEqual(wrapper.hangTypeFormatter(true, true), "hang_type")
        XCTAssertEqual(wrapper.issueReporter.fatalHangsAsCrashes, false)
        XCTAssertEqual(wrapper.issueReporter.firebaseHangReason, "my_reason")

        // cleanup PerformanceSuite
        try PerformanceMonitoring.disable()
    }

    func testEnableWithDisabledCrashlytics() async throws {
        let settings = CrashlyticsHangsSettings()
        // it shouldn't crash without crashlytics initialized
        try PerformanceMonitoring.enableWithCrashlyticsSupport(config: .all(receiver: self), settings: settings, crashlyticsEnabledInDebug: false)

        let hangReporter = try XCTUnwrap(PerformanceMonitoring.appReporters.compactMap { $0 as? HangReporter }.first)
        // check that hangsReceiver is not wrapped
        XCTAssertTrue(hangReporter.receiver is PerformanceMonitoringTests)

        // cleanup PerformanceSuite
        try PerformanceMonitoring.disable()
    }

    private func customHangTypeFormatter(_ fatal: Bool, _ startup: Bool) -> String {
        return "hang_type"
    }

    private var onInitExpectation: XCTestExpectation?
}

extension PerformanceMonitoringTests: PerformanceSuiteMetricsReceiver {
    typealias ScreenIdentifier = String

    func screenIdentifier(for viewController: UIViewController) -> String? {
        return String(describing: type(of: viewController))
    }

    func appRenderingMetricsReceived(metrics: PerformanceSuite.RenderingMetrics) {

    }

    func fragmentTTIMetricsReceived(metrics: PerformanceSuite.TTIMetrics, fragment identifier: String) {

    }

    func fatalHangReceived(info: PerformanceSuite.HangInfo) {

    }

    func nonFatalHangReceived(info: PerformanceSuite.HangInfo) {

    }

    func hangStarted(info: PerformanceSuite.HangInfo) {
    }

    func renderingMetricsReceived(metrics: PerformanceSuite.RenderingMetrics, screen: String) {
    }

    func startupTimeReceived(_ data: PerformanceSuite.StartupTimeData) {
    }

    func ttiMetricsReceived(metrics: PerformanceSuite.TTIMetrics, screen: String) {
    }

    func viewControllerLeakReceived(viewController: UIViewController) {
    }

    func onInit(screen: String) {
        onInitExpectation?.fulfill()
    }

    func onViewDidLoad(screen: String) {
    }

    func onViewWillAppear(screen: String) {
    }

    func onViewDidAppear(screen: String) {
    }

    func onViewWillDisappear(screen: String) {
    }

    func onViewDidDisappear(screen: String) {
    }

    func watchdogTerminationReceived(_ data: PerformanceSuite.WatchdogTerminationData) {
    }
}
