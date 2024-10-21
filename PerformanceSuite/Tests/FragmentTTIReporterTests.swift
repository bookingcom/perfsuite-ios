//
//  FragmentTTIReporterTests.swift
//  PerformanceSuite-Tests
//
//  Created by Gleb Tarasov on 21/12/2022.
//

import XCTest

@testable import PerformanceSuite

final class FragmentTTIReporterTests: XCTestCase {

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    func testFragmentTTIWasReported() {

        let metricsReceiver = FragmentTTIMetricsReceiverStub()

        XCTAssertNil(metricsReceiver.metrics)
        XCTAssertNil(metricsReceiver.identifier)

        let appStateListener = AppStateListenerStub()
        let timeProvider = TimeProviderStub()
        let time = DispatchTime.now()

        timeProvider.time = time
        let reporter = FragmentTTIReporter(
            metricsReceiver: metricsReceiver, timeProvider: timeProvider, appStateListenerFactory: { appStateListener })

        let trackable = reporter.start(identifier: "my_identifier")
        timeProvider.time = time.advanced(by: .seconds(10))
        trackable.fragmentIsReady()

        PerformanceMonitoring.queue.sync {}
        PerformanceMonitoring.consumerQueue.sync {}

        XCTAssertNotNil(metricsReceiver.metrics)
        XCTAssertNotNil(metricsReceiver.identifier)

        XCTAssertEqual(metricsReceiver.identifier, "my_identifier")
        XCTAssertEqual(metricsReceiver.metrics?.tti.seconds, 10)
        XCTAssertEqual(metricsReceiver.metrics?.ttfr.seconds, 10)
    }

    func testFragmentTTFRWasReported() {
        let metricsReceiver = FragmentTTIMetricsReceiverStub()

        XCTAssertNil(metricsReceiver.metrics)
        XCTAssertNil(metricsReceiver.identifier)

        let appStateListener = AppStateListenerStub()
        let timeProvider = TimeProviderStub()
        let time = DispatchTime.now()

        timeProvider.time = time
        let reporter = FragmentTTIReporter(
            metricsReceiver: metricsReceiver, timeProvider: timeProvider, appStateListenerFactory: { appStateListener })

        let trackable = reporter.start(identifier: "my_identifier")
        timeProvider.time = time.advanced(by: .seconds(10))
        trackable.fragmentIsRendered()

        PerformanceMonitoring.queue.sync {}
        PerformanceMonitoring.consumerQueue.sync {}

        timeProvider.time = time.advanced(by: .seconds(120))
        trackable.fragmentIsReady()

        PerformanceMonitoring.queue.sync {}
        PerformanceMonitoring.consumerQueue.sync {}

        XCTAssertNotNil(metricsReceiver.metrics)
        XCTAssertNotNil(metricsReceiver.identifier)

        XCTAssertEqual(metricsReceiver.identifier, "my_identifier")
        XCTAssertEqual(metricsReceiver.metrics?.tti.seconds, 120)
        XCTAssertEqual(metricsReceiver.metrics?.ttfr.seconds, 10)
    }

    func testConsecutiveCallDoesNotSendMoreData() {
        let metricsReceiver = FragmentTTIMetricsReceiverStub()

        XCTAssertNil(metricsReceiver.metrics)
        XCTAssertNil(metricsReceiver.identifier)

        let appStateListener = AppStateListenerStub()
        let timeProvider = TimeProviderStub()
        let time = DispatchTime.now()

        timeProvider.time = time
        let reporter = FragmentTTIReporter(
            metricsReceiver: metricsReceiver, timeProvider: timeProvider, appStateListenerFactory: { appStateListener })

        let trackable = reporter.start(identifier: "my_identifier")
        timeProvider.time = time.advanced(by: .seconds(10))
        trackable.fragmentIsReady()

        PerformanceMonitoring.queue.sync {}
        PerformanceMonitoring.consumerQueue.sync {}

        XCTAssertNotNil(metricsReceiver.metrics)
        XCTAssertNotNil(metricsReceiver.identifier)

        metricsReceiver.clear()

        trackable.fragmentIsReady()

        PerformanceMonitoring.queue.sync {}
        PerformanceMonitoring.consumerQueue.sync {}

        XCTAssertNil(metricsReceiver.metrics)
        XCTAssertNil(metricsReceiver.identifier)
    }

    func testFragmentTTINotReportedWhenWasInBackground() {
        let metricsReceiver = FragmentTTIMetricsReceiverStub()

        XCTAssertNil(metricsReceiver.metrics)
        XCTAssertNil(metricsReceiver.identifier)

        let appStateListener = AppStateListenerStub()
        let timeProvider = TimeProviderStub()
        let time = DispatchTime.now()

        timeProvider.time = time
        let reporter = FragmentTTIReporter(
            metricsReceiver: metricsReceiver, timeProvider: timeProvider, appStateListenerFactory: { appStateListener })

        let trackable = reporter.start(identifier: "my_identifier")
        timeProvider.time = time.advanced(by: .seconds(10))
        appStateListener.wasInBackground = true
        trackable.fragmentIsReady()

        PerformanceMonitoring.queue.sync {}
        PerformanceMonitoring.consumerQueue.sync {}

        XCTAssertNil(metricsReceiver.metrics)
        XCTAssertNil(metricsReceiver.identifier)
    }

    func testPerformanceSuiteIntegration() throws {

        let fragment = PerformanceMonitoring.startFragmentTTI(identifier: "throws")

        // preconditionFailure should be raised, because we haven't registered FragmentTTIReceiver
        let exp1 = expectation(description: "preconditionFailure1")
        preconditionFailureQueue.sync {
            preconditionFailureExpectation = exp1
        }
        DispatchQueue.global().async {
            fragment.fragmentIsReady()
        }
        wait(for: [exp1], timeout: 1)

        // preconditionFailure should be raised, because we haven't registered FragmentTTIReceiver
        let exp2 = expectation(description: "preconditionFailure2")
        preconditionFailureQueue.sync {
            preconditionFailureExpectation = exp2
        }
        DispatchQueue.global().async {
            fragment.fragmentIsRendered()
        }
        wait(for: [exp2], timeout: 1)
        preconditionFailureQueue.sync {
            XCTAssertNil(preconditionFailureExpectation)
        }

        let metricsReciever = FragmentTTIMetricsReceiverStub()
        let config = ConfigItem.fragmentTTI(metricsReciever)
        try PerformanceMonitoring.enable(config: [config])

        let trackable = PerformanceMonitoring.startFragmentTTI(identifier: "new_identifier")
        let exp = expectation(description: "wait")
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(3)) {
            trackable.fragmentIsReady()
            exp.fulfill()
        }
        waitForExpectations(timeout: 1)

        PerformanceMonitoring.queue.sync {}
        PerformanceMonitoring.consumerQueue.sync {}

        XCTAssertEqual(metricsReciever.identifier, "new_identifier")
        let tti = try XCTUnwrap(metricsReciever.metrics?.tti.milliseconds)
        XCTAssertGreaterThanOrEqual(tti, 3)

        try PerformanceMonitoring.disable()
    }

    func testFragmentTTIIsReportedWhenWasInBackgroundButNotNow() throws {
        let metricsReciever = FragmentTTIMetricsReceiverStub()
        let config = ConfigItem.fragmentTTI(metricsReciever)
        try PerformanceMonitoring.enable(config: [config])

        let trackable1 = PerformanceMonitoring.startFragmentTTI(identifier: "in_background")
        NotificationCenter.default.post(name: UIApplication.willResignActiveNotification, object: nil)
        NotificationCenter.default.post(name: UIApplication.didBecomeActiveNotification, object: nil)
        trackable1.fragmentIsReady()

        PerformanceMonitoring.queue.sync {}
        PerformanceMonitoring.consumerQueue.sync {}

        // App was in background, no TTI generated
        XCTAssertNil(metricsReciever.identifier)
        XCTAssertNil(metricsReciever.identifier)
        XCTAssertNil(metricsReciever.metrics?.tti)

        let trackable2 = PerformanceMonitoring.startFragmentTTI(identifier: "not_in_background")
        let exp = expectation(description: "wait")
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(3)) {
            trackable2.fragmentIsReady()
            exp.fulfill()
        }
        waitForExpectations(timeout: 1)

        PerformanceMonitoring.queue.sync {}
        PerformanceMonitoring.consumerQueue.sync {}

        // App wasn't in background
        XCTAssertEqual(metricsReciever.identifier, "not_in_background")
        let tti = try XCTUnwrap(metricsReciever.metrics?.tti.milliseconds)
        XCTAssertGreaterThanOrEqual(tti, 3)

        try PerformanceMonitoring.disable()
    }
}

private class FragmentTTIMetricsReceiverStub: FragmentTTIMetricsReceiver {
    func fragmentTTIMetricsReceived(metrics: TTIMetrics, fragment identifier: String) {
        self.identifier = identifier
        self.metrics = metrics
    }

    var metrics: TTIMetrics?
    var identifier: String?

    func clear() {
        metrics = nil
        identifier = nil
    }
}

@_dynamicReplacement(for: preconditionFailure)
func preconditionFailureInTests(message: String, file: StaticString, line: UInt) {
    let expectation = preconditionFailureQueue.sync {
        preconditionFailureExpectation
    }

    if expectation != nil {
        preconditionFailureQueue.sync {
            preconditionFailureExpectation = nil
        }
        expectation?.fulfill()
    } else {
        Swift.preconditionFailure(message, file: file, line: line)
    }
}
private var preconditionFailureExpectation: XCTestExpectation?
private let preconditionFailureQueue = DispatchQueue(label: "preconditionFailureQueue")
