//
//  FragmentRenderingReporterTests.swift
//  PerformanceSuite-Tests
//
//  Created by Luis Resende on 12/10/2026.
//

import XCTest

@testable import PerformanceSuite

final class FragmentRenderingReporterTests: XCTestCase {

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    func testFragmentRenderingMetricsAreReported() {
        let metricsReceiver = FragmentRenderingMetricsReceiverStub()
        let framesMeter = FragmentFramesMeterStub()
        let appStateListener = AppStateListenerStub()

        let reporter = FragmentRenderingReporter(
            metricsReceiver: metricsReceiver, framesMeter: framesMeter, appStateListenerFactory: { appStateListener })

        let trackable = reporter.start(identifier: "my_fragment")

        PerformanceMonitoring.queue.sync {}

        XCTAssertTrue(framesMeter.isStarted)

        PerformanceMonitoring.queue.sync {
            framesMeter.report(frameDuration: 0.032, refreshRateDuration: 0.016)
            framesMeter.report(frameDuration: 0.016, refreshRateDuration: 0.016)
            framesMeter.report(frameDuration: 0.016, refreshRateDuration: 0.016)
        }

        trackable.fragmentRenderingFinished()

        PerformanceMonitoring.queue.sync {}
        PerformanceMonitoring.consumerQueue.sync {}

        XCTAssertNotNil(metricsReceiver.renderingMetrics)
        XCTAssertEqual(metricsReceiver.identifier, "my_fragment")
        XCTAssertEqual(metricsReceiver.renderingMetrics?.renderedFrames, 3)
        XCTAssertFalse(framesMeter.isStarted)
    }

    func testConsecutiveCallDoesNotSendMoreData() {
        let metricsReceiver = FragmentRenderingMetricsReceiverStub()
        let framesMeter = FragmentFramesMeterStub()
        let appStateListener = AppStateListenerStub()

        let reporter = FragmentRenderingReporter(
            metricsReceiver: metricsReceiver, framesMeter: framesMeter, appStateListenerFactory: { appStateListener })

        let trackable = reporter.start(identifier: "my_fragment")

        PerformanceMonitoring.queue.sync {
            framesMeter.report(frameDuration: 0.016, refreshRateDuration: 0.016)
        }

        trackable.fragmentRenderingFinished()

        PerformanceMonitoring.queue.sync {}
        PerformanceMonitoring.consumerQueue.sync {}

        XCTAssertNotNil(metricsReceiver.renderingMetrics)

        metricsReceiver.clear()

        trackable.fragmentRenderingFinished()

        PerformanceMonitoring.queue.sync {}
        PerformanceMonitoring.consumerQueue.sync {}

        XCTAssertNil(metricsReceiver.renderingMetrics)
    }

    func testNotReportedWhenWasInBackground() {
        let metricsReceiver = FragmentRenderingMetricsReceiverStub()
        let framesMeter = FragmentFramesMeterStub()
        let appStateListener = AppStateListenerStub()

        let reporter = FragmentRenderingReporter(
            metricsReceiver: metricsReceiver, framesMeter: framesMeter, appStateListenerFactory: { appStateListener })

        let trackable = reporter.start(identifier: "my_fragment")

        PerformanceMonitoring.queue.sync {
            framesMeter.report(frameDuration: 0.016, refreshRateDuration: 0.016)
        }
        appStateListener.wasInBackground = true
        trackable.fragmentRenderingFinished()

        PerformanceMonitoring.queue.sync {}
        PerformanceMonitoring.consumerQueue.sync {}

        XCTAssertNil(metricsReceiver.renderingMetrics)
        XCTAssertNil(metricsReceiver.identifier)
    }

    func testMultipleConcurrentFragmentsTrackIndependently() {
        let metricsReceiver = FragmentRenderingMetricsReceiverStub()
        let framesMeter = FragmentFramesMeterStub()
        let appStateListener = AppStateListenerStub()

        let reporter = FragmentRenderingReporter(
            metricsReceiver: metricsReceiver, framesMeter: framesMeter, appStateListenerFactory: { appStateListener })

        let trackable1 = reporter.start(identifier: "fragment_a")
        let trackable2 = reporter.start(identifier: "fragment_b")

        PerformanceMonitoring.queue.sync {
            framesMeter.report(frameDuration: 0.032, refreshRateDuration: 0.016)
        }

        trackable1.fragmentRenderingFinished()

        PerformanceMonitoring.queue.sync {}
        PerformanceMonitoring.consumerQueue.sync {}

        XCTAssertEqual(metricsReceiver.identifier, "fragment_a")
        let metricsA = metricsReceiver.renderingMetrics
        XCTAssertNotNil(metricsA)

        metricsReceiver.clear()

        PerformanceMonitoring.queue.sync {
            framesMeter.report(frameDuration: 0.016, refreshRateDuration: 0.016)
        }

        trackable2.fragmentRenderingFinished()

        PerformanceMonitoring.queue.sync {}
        PerformanceMonitoring.consumerQueue.sync {}

        XCTAssertEqual(metricsReceiver.identifier, "fragment_b")
        XCTAssertNotNil(metricsReceiver.renderingMetrics)
    }

    func testAbandonedTrackableDoesNotReport() {
        let metricsReceiver = FragmentRenderingMetricsReceiverStub()
        let framesMeter = FragmentFramesMeterStub()
        let appStateListener = AppStateListenerStub()

        let reporter = FragmentRenderingReporter(
            metricsReceiver: metricsReceiver, framesMeter: framesMeter, appStateListenerFactory: { appStateListener })

        autoreleasepool {
            _ = reporter.start(identifier: "abandoned")
            PerformanceMonitoring.queue.sync {
                framesMeter.report(frameDuration: 0.016, refreshRateDuration: 0.016)
            }
        }

        PerformanceMonitoring.queue.sync {}
        PerformanceMonitoring.consumerQueue.sync {}

        XCTAssertNil(metricsReceiver.renderingMetrics)
        XCTAssertNil(metricsReceiver.identifier)
    }

    func testPerformanceSuiteIntegration() throws {
        let fragment = PerformanceMonitoring.startFragmentRendering(identifier: "throws")

        let exp1 = expectation(description: "preconditionFailure1")
        preconditionFailureQueue.sync {
            preconditionFailureExpectation = exp1
        }
        DispatchQueue.global().async {
            fragment.fragmentRenderingFinished()
        }
        wait(for: [exp1], timeout: 1)
        preconditionFailureQueue.sync {
            XCTAssertNil(preconditionFailureExpectation)
        }

        let metricsReceiver = FragmentRenderingMetricsReceiverStub()
        let config: Config = [
            .fragmentRendering(metricsReceiver),
            .appLevelRendering(FragmentTestAppRenderingReceiverStub()),
        ]
        try PerformanceMonitoring.enable(
            config: config,
            experiments: Experiments(fragmentRenderingMetrics: true)
        )

        let trackable = PerformanceMonitoring.startFragmentRendering(identifier: "new_fragment")
        let exp = expectation(description: "wait")
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(50)) {
            trackable.fragmentRenderingFinished()
            exp.fulfill()
        }
        waitForExpectations(timeout: 2)

        PerformanceMonitoring.queue.sync {}
        PerformanceMonitoring.consumerQueue.sync {}

        XCTAssertEqual(metricsReceiver.identifier, "new_fragment")

        try PerformanceMonitoring.disable()
    }

    func testNoMetricsReportedWhenNoFramesTicked() {
        let metricsReceiver = FragmentRenderingMetricsReceiverStub()
        let framesMeter = FragmentFramesMeterStub()
        let appStateListener = AppStateListenerStub()

        let reporter = FragmentRenderingReporter(
            metricsReceiver: metricsReceiver, framesMeter: framesMeter, appStateListenerFactory: { appStateListener })

        let trackable = reporter.start(identifier: "empty")

        PerformanceMonitoring.queue.sync {}

        trackable.fragmentRenderingFinished()

        PerformanceMonitoring.queue.sync {}
        PerformanceMonitoring.consumerQueue.sync {}

        XCTAssertNil(metricsReceiver.renderingMetrics)
    }
}

// MARK: - Stubs

private class FragmentRenderingMetricsReceiverStub: FragmentRenderingMetricsReceiver {
    func fragmentRenderingMetricsReceived(metrics: RenderingMetrics, fragment identifier: String) {
        self.identifier = identifier
        self.renderingMetrics = metrics
    }

    var renderingMetrics: RenderingMetrics?
    var identifier: String?

    func clear() {
        renderingMetrics = nil
        identifier = nil
    }
}

private class FragmentTestAppRenderingReceiverStub: AppRenderingMetricsReceiver {
    func appRenderingMetricsReceived(metrics: RenderingMetrics) {}
}

private class FragmentFramesMeterStub: FramesMeter {
    private var receivers = NSHashTable<AnyObject>.weakObjects()

    func subscribe(receiver: FramesMeterReceiver) {
        receivers.add(receiver as AnyObject)
    }

    func unsubscribe(receiver: FramesMeterReceiver) {
        receivers.remove(receiver as AnyObject)
    }

    func report(frameDuration: CFTimeInterval, refreshRateDuration: CFTimeInterval) {
        for receiver in receivers.allObjects {
            (receiver as? FramesMeterReceiver)?.frameTicked(
                frameDuration: frameDuration, refreshRateDuration: refreshRateDuration)
        }
    }

    var isStarted: Bool {
        return receivers.count > 0
    }
}
