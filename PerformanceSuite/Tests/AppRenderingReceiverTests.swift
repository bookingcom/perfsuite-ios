//
//  AppRenderingReceiverTests.swift
//  PerformanceSuite-Tests
//
//  Created by Gleb Tarasov on 21/12/2021.
//

import XCTest

@testable import PerformanceSuite

class AppRenderingReceiverTests: XCTestCase {

    override func setUp() {
        super.setUp()

        PerformanceMonitoring.queue.sync {}
        self.previousQueue = PerformanceMonitoring.changeQueueForTests(DispatchQueue.main)
    }
    private var previousQueue: DispatchQueue?

    override func tearDown() {
        super.tearDown()
        if let previousQueue = previousQueue {
            PerformanceMonitoring.changeQueueForTests(previousQueue)
        }
    }

    func testFramesMeterIsDelayedOnLaunch() {
        let metricsReceiver = AppRenderingMetricsReceiverStub()
        let framesMeter = FramesMeterStub()
        let receiver = AppRenderingReporter(
            metricsReceiver: metricsReceiver, framesMeter: framesMeter, sendingThrottleInterval: throttleInterval)
        XCTAssertFalse(framesMeter.isStarted)
        let exp = expectation(description: "throttle delay")
        DispatchQueue.main.asyncAfter(deadline: .now() + throttleInterval * 2) {
            XCTAssertTrue(framesMeter.isStarted)
            exp.fulfill()
        }

        waitForExpectations(timeout: 1, handler: nil)
        _ = receiver
    }

    func testSingleSending() {
        let metricsReceiver = AppRenderingMetricsReceiverStub()
        let framesMeter = FramesMeterStub()
        let receiver = AppRenderingReporter(
            metricsReceiver: metricsReceiver, framesMeter: framesMeter, sendingThrottleInterval: throttleInterval)

        // should be ignored, not started yet
        framesMeter.report(frameDuration: 0.016 * 100_000, refreshRateDuration: 0.016)

        waitForThreshold()

        framesMeter.report(frameDuration: 0.016 * 50_000, refreshRateDuration: 0.016)
        XCTAssertNil(metricsReceiver.appRenderingMetrics)

        waitForThreshold()
        PerformanceMonitoring.consumerQueue.sync {}

        XCTAssertNotNil(metricsReceiver.appRenderingMetrics)
        if let metrics = metricsReceiver.appRenderingMetrics {
            XCTAssertEqual(metrics.expectedFrames, 50_000)
            XCTAssertEqual(metrics.renderedFrames, 1)
            XCTAssertEqual(metrics.droppedFrames, 49_999)
            XCTAssertEqual(metrics.slowFrames, 1)
            XCTAssertEqual(metrics.frozenFrames, 1)
        }

        _ = receiver
    }

    func testSeveralSendings() {
        let metricsReceiver = AppRenderingMetricsReceiverStub()
        let framesMeter = FramesMeterStub()
        let receiver = AppRenderingReporter(
            metricsReceiver: metricsReceiver, framesMeter: framesMeter, sendingThrottleInterval: throttleInterval)

        waitForThreshold()

        framesMeter.report(frameDuration: 0.1, refreshRateDuration: 0.016)
        waitForThreshold()
        PerformanceMonitoring.consumerQueue.sync {}

        XCTAssertNotNil(metricsReceiver.appRenderingMetrics)
        if let metrics = metricsReceiver.appRenderingMetrics {
            XCTAssertEqual(metrics.expectedFrames, Int(round(0.1 / 0.016)))
            XCTAssertEqual(metrics.renderedFrames, 1)
            XCTAssertEqual(metrics.droppedFrames, Int(round(0.1 / 0.016) - 1))
            XCTAssertEqual(metrics.slowFrames, 1)
            XCTAssertEqual(metrics.frozenFrames, 0)
        }

        framesMeter.report(frameDuration: 1.1, refreshRateDuration: 0.016)
        waitForThreshold()
        PerformanceMonitoring.consumerQueue.sync {}

        XCTAssertNotNil(metricsReceiver.appRenderingMetrics)
        if let metrics = metricsReceiver.appRenderingMetrics {
            XCTAssertEqual(metrics.expectedFrames, Int(round(1.1 / 0.016)))
            XCTAssertEqual(metrics.renderedFrames, 1)
            XCTAssertEqual(metrics.droppedFrames, Int(round(1.1 / 0.016) - 1))
            XCTAssertEqual(metrics.slowFrames, 1)
            XCTAssertEqual(metrics.frozenFrames, 1)
        }

        _ = receiver
    }

    func testBulkSending() {
        let metricsReceiver = AppRenderingMetricsReceiverStub()
        let framesMeter = FramesMeterStub()
        let receiver = AppRenderingReporter(
            metricsReceiver: metricsReceiver, framesMeter: framesMeter, sendingThrottleInterval: throttleInterval)

        waitForThreshold()

        var droppedFrames = 0
        var totalFrames = 0

        framesMeter.report(frameDuration: 0.016, refreshRateDuration: 0.016)
        totalFrames += 1
        XCTAssertNil(metricsReceiver.appRenderingMetrics)

        framesMeter.report(frameDuration: 10 * 0.016, refreshRateDuration: 0.016)
        droppedFrames += 9
        totalFrames += 10
        XCTAssertNil(metricsReceiver.appRenderingMetrics)

        framesMeter.report(frameDuration: 0.016, refreshRateDuration: 0.016)
        totalFrames += 1
        XCTAssertNil(metricsReceiver.appRenderingMetrics)

        framesMeter.report(frameDuration: 20 * 0.016, refreshRateDuration: 0.016)
        droppedFrames += 19
        totalFrames += 20
        XCTAssertNil(metricsReceiver.appRenderingMetrics)

        framesMeter.report(frameDuration: 0.016, refreshRateDuration: 0.016)
        totalFrames += 1
        XCTAssertNil(metricsReceiver.appRenderingMetrics)

        framesMeter.report(frameDuration: 40 * 0.016, refreshRateDuration: 0.016)
        droppedFrames += 39
        totalFrames += 40
        XCTAssertNil(metricsReceiver.appRenderingMetrics)

        waitForThreshold()
        PerformanceMonitoring.consumerQueue.sync {}

        XCTAssertNotNil(metricsReceiver.appRenderingMetrics)
        if let metrics = metricsReceiver.appRenderingMetrics {
            XCTAssertEqual(metrics.expectedFrames, totalFrames)
            XCTAssertEqual(metrics.renderedFrames, totalFrames - droppedFrames)
            XCTAssertEqual(metrics.droppedFrames, droppedFrames)
            XCTAssertEqual(metrics.slowFrames, 3)
            XCTAssertEqual(metrics.frozenFrames, 0)
        }

        _ = receiver
    }

    func testNoDroppedFramesAreNotSent() {
        let metricsReceiver = AppRenderingMetricsReceiverStub()
        let framesMeter = FramesMeterStub()
        let receiver = AppRenderingReporter(
            metricsReceiver: metricsReceiver, framesMeter: framesMeter, sendingThrottleInterval: throttleInterval)

        waitForThreshold()

        // shouldn't be counted, no dropped frames, will go to the next bulk
        framesMeter.report(frameDuration: 0.016, refreshRateDuration: 0.016)
        framesMeter.report(frameDuration: 0.016, refreshRateDuration: 0.016)

        waitForThreshold()
        PerformanceMonitoring.consumerQueue.sync {}

        XCTAssertNil(metricsReceiver.appRenderingMetrics)
        _ = receiver
    }

    func testWillResignActiveEndsSessionSynchronously() {
        let metricsReceiver = LiveAppRenderingMetricsReceiverStub()
        let framesMeter = FramesMeterStub()
        let receiver = AppRenderingReporter(
            metricsReceiver: metricsReceiver, framesMeter: framesMeter, sendingThrottleInterval: throttleInterval)

        // willResignActive fires before the backend's didEnterBackground session-end, so the live
        // session must end *synchronously* within the notification turn to win that race — no wait.
        NotificationCenter.default.post(name: UIApplication.willResignActiveNotification, object: nil)

        XCTAssertEqual(
            metricsReceiver.endedCount, 1,
            "willResignActive must end the live session synchronously so it beats the backend session-end")
        _ = receiver
    }

    func testDidBecomeActiveStartsSession() {
        let metricsReceiver = LiveAppRenderingMetricsReceiverStub()
        let framesMeter = FramesMeterStub()
        let receiver = AppRenderingReporter(
            metricsReceiver: metricsReceiver, framesMeter: framesMeter, sendingThrottleInterval: throttleInterval)

        NotificationCenter.default.post(name: UIApplication.didBecomeActiveNotification, object: nil)
        PerformanceMonitoring.consumerQueue.sync {}

        XCTAssertEqual(metricsReceiver.startedCount, 1, "didBecomeActive must start a new live session")
        _ = receiver
    }

    func testBackgroundCycleEndsThenRestarts() {
        let metricsReceiver = LiveAppRenderingMetricsReceiverStub()
        let framesMeter = FramesMeterStub()
        let receiver = AppRenderingReporter(
            metricsReceiver: metricsReceiver, framesMeter: framesMeter, sendingThrottleInterval: throttleInterval)

        NotificationCenter.default.post(name: UIApplication.didBecomeActiveNotification, object: nil)
        PerformanceMonitoring.consumerQueue.sync {}
        NotificationCenter.default.post(name: UIApplication.willResignActiveNotification, object: nil)
        NotificationCenter.default.post(name: UIApplication.didBecomeActiveNotification, object: nil)
        PerformanceMonitoring.consumerQueue.sync {}

        XCTAssertEqual(metricsReceiver.startedCount, 2, "each foreground entry starts a fresh session")
        XCTAssertEqual(metricsReceiver.endedCount, 1, "willResignActive ended the first session")
        _ = receiver
    }

    private func waitForThreshold() {
        let exp = expectation(description: "throttle delay")
        DispatchQueue.main.asyncAfter(deadline: .now() + throttleInterval * 2) {
            exp.fulfill()
        }
        waitForExpectations(timeout: 1, handler: nil)
    }

    let throttleInterval: TimeInterval = 0.001
}

class AppRenderingMetricsReceiverStub: AppRenderingMetricsReceiver {
    func appRenderingMetricsReceived(metrics: RenderingMetrics) {
        appRenderingMetrics = metrics
    }
    var appRenderingMetrics: RenderingMetrics?
}

/// Live variant used by the app-lifecycle (willResignActive / didBecomeActive) tests: records
/// session start/end calls so the background-safe live-span lifecycle can be asserted.
final class LiveAppRenderingMetricsReceiverStub: LiveAppRenderingMetricsReceiver {
    var appRenderingMetrics: RenderingMetrics?
    var startedCount = 0
    var endedCount = 0
    func appRenderingMetricsReceived(metrics: RenderingMetrics) {
        appRenderingMetrics = metrics
    }
    func appRenderingSessionStarted(at startedAt: Date) {
        startedCount += 1
    }
    func appRenderingSessionEnded() {
        endedCount += 1
    }
}
