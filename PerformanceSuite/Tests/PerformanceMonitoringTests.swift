//
//  PerformanceMonitoringTests.swift
//  PerformanceSuite-Tests
//
//  Created by Gleb Tarasov on 25/09/2023.
//

import XCTest
@testable import PerformanceSuite

final class PerformanceMonitoringTests: XCTestCase {

    override func setUp() {
        super.setUp()
        StartupTimeReporter.forgetMainStartedForTests()
    }

    override func tearDown() {
        super.tearDown()
        StartupTimeReporter.forgetMainStartedForTests()
    }

    func testIntegration() throws {
        PerformanceMonitoring.onMainStarted()
        try PerformanceMonitoring.enable(config: .all(receiver: self))

        let exp = expectation(description: "onInit")
        onInitExpectation = exp
        let vc = UIViewController()
        wait(for: [exp], timeout: 0.5)
        _ = vc
        try PerformanceMonitoring.disable()

        let exp2 = expectation(description: "onInit2")
        exp2.isInverted = true
        onInitExpectation = exp2
        let vc2 = UIViewController()
        wait(for: [exp2], timeout: 0.5)
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

    private var onInitExpectation: XCTestExpectation?
}

extension PerformanceMonitoringTests: PerformanceSuiteMetricsReceiver {
    func appRenderingMetricsReceived(metrics: PerformanceSuite.RenderingMetrics) {

    }

    func fragmentTTIMetricsReceived(metrics: PerformanceSuite.TTIMetrics, identifier: String) {

    }

    func fatalHangReceived(info: PerformanceSuite.HangInfo) {

    }

    func nonFatalHangReceived(info: PerformanceSuite.HangInfo) {

    }

    func hangStarted(info: PerformanceSuite.HangInfo) {
    }

    func renderingMetricsReceived(metrics: PerformanceSuite.RenderingMetrics, viewController: UIViewController) {
    }

    func startupTimeReceived(_ data: PerformanceSuite.StartupTimeData) {
    }

    func ttiMetricsReceived(metrics: PerformanceSuite.TTIMetrics, viewController: UIViewController) {
    }

    func viewControllerLeakReceived(viewController: UIViewController) {
    }

    func key(for viewController: UIViewController) -> String {
        return String(describing: type(of: viewController))
    }

    func onInit(viewControllerKey: String) {
        onInitExpectation?.fulfill()
    }

    func onViewDidLoad(viewControllerKey: String) {
    }

    func onViewWillAppear(viewControllerKey: String) {
    }

    func onViewDidAppear(viewControllerKey: String) {
    }

    func onViewWillDisappear(viewControllerKey: String) {
    }

    func onViewDidDisappear(viewControllerKey: String) {
    }

    func watchdogTerminationReceived(_ data: PerformanceSuite.WatchdogTerminationData) {
    }
}
