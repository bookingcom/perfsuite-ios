//
//  RenderingObserverTests.swift
//  PerformanceSuite
//
//  Created by Gleb Tarasov on 07/07/2021.
//

import XCTest

@testable import PerformanceSuite

// swiftlint:disable force_unwrapping


class RenderingObserverTests: XCTestCase {

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

    func testRenderingObserver() {
        let metricsReceiver = RenderingMetricsReceiverStub()
        let framesMeter = FramesMeterStub()
        let observer = RenderingObserver(metricsReceiver: metricsReceiver, framesMeter: framesMeter)

        let vc = UIViewController()

        waitForEvents()

        // should be ignored
        framesMeter.report(frameDuration: 160, refreshRateDuration: 0.016)

        observer.beforeInit(viewController: vc)
        waitForEvents()

        // should be ignored
        framesMeter.report(frameDuration: 1600, refreshRateDuration: 0.016)

        observer.afterViewWillAppear(viewController: vc)
        waitForEvents()

        // should be ignored
        framesMeter.report(frameDuration: 16000, refreshRateDuration: 0.016)

        observer.afterViewDidAppear(viewController: vc)
        waitForEvents()

        var expectedDroppedFrames = 0
        var expectedFreezeTime = 0
        var expectedSessionDuration = 0

        // should be tracked, 9 dropped frames, 1 rendered frame, 1 slow frame, 0 frozen frames, 10 expected frames
        framesMeter.report(frameDuration: 0.16, refreshRateDuration: 0.016)
        expectedDroppedFrames += 9
        expectedFreezeTime += 160 - 16
        expectedSessionDuration += 160


        // should be tracked, 49 dropped frames, 1 rendered frame, 1 slow frame, 1 frozen frame, 50 expected frames
        framesMeter.report(frameDuration: 0.8, refreshRateDuration: 0.016)
        expectedDroppedFrames += 49
        expectedFreezeTime += 800 - 16
        expectedSessionDuration += 800

        observer.beforeViewWillDisappear(viewController: vc)
        waitForEvents()

        // should be ignored
        framesMeter.report(frameDuration: 160000, refreshRateDuration: 0.016)

        waitForEvents()

        XCTAssertEqual(metricsReceiver.renderingMetrics!.renderedFrames, 2)
        XCTAssertEqual(metricsReceiver.renderingMetrics!.expectedFrames, 60)

        XCTAssertEqual(metricsReceiver.renderingMetrics!.slowFrames, 2)
        XCTAssertEqual(metricsReceiver.renderingMetrics!.frozenFrames, 1)
        XCTAssertEqual(metricsReceiver.renderingMetrics!.droppedFrames, expectedDroppedFrames)
        XCTAssertEqual(metricsReceiver.renderingMetrics!.freezeTime.milliseconds, expectedFreezeTime)
        XCTAssertEqual(metricsReceiver.renderingMetrics!.sessionDuration.milliseconds, expectedSessionDuration)

        XCTAssertEqual(metricsReceiver.renderingMetrics!.slowFramesRatio, 1)
        XCTAssertEqual(metricsReceiver.renderingMetrics!.frozenFramesRatio, 0.5)
        XCTAssertEqual(metricsReceiver.renderingMetrics!.droppedFramesRatio, Decimal(expectedDroppedFrames) / 60)
    }

    func testRenderingObserverIsResetAfterViewDisappeared() {
        let metricsReceiver = RenderingMetricsReceiverStub()
        let framesMeter = FramesMeterStub()
        let observer = RenderingObserver(metricsReceiver: metricsReceiver, framesMeter: framesMeter)

        let vc = UIViewController()

        observer.beforeInit(viewController: vc)
        observer.afterViewWillAppear(viewController: vc)
        observer.afterViewDidAppear(viewController: vc)
        waitForEvents()

        // 9 dropped frames, 10 expected frames, 1 slow, 0 frozen
        framesMeter.report(frameDuration: 0.16, refreshRateDuration: 0.016)

        observer.beforeViewWillDisappear(viewController: vc)
        waitForEvents()

        XCTAssertEqual(metricsReceiver.renderingMetrics!.expectedFrames, 10)
        XCTAssertEqual(metricsReceiver.renderingMetrics!.droppedFrames, 9)
        XCTAssertEqual(metricsReceiver.renderingMetrics!.freezeTime.milliseconds, 160 - 16)
        XCTAssertEqual(metricsReceiver.renderingMetrics!.sessionDuration.milliseconds, 160)
        XCTAssertEqual(metricsReceiver.renderingMetrics!.slowFrames, 1)
        XCTAssertEqual(metricsReceiver.renderingMetrics!.frozenFrames, 0)
        metricsReceiver.renderingMetrics = nil

        observer.afterViewWillAppear(viewController: vc)
        observer.afterViewDidAppear(viewController: vc)
        waitForEvents()

        // 49 dropped frames, 50 expected frames, 1 slow, 1 frozen
        framesMeter.report(frameDuration: 0.8, refreshRateDuration: 0.016)

        observer.beforeViewWillDisappear(viewController: vc)
        waitForEvents()

        XCTAssertEqual(metricsReceiver.renderingMetrics!.expectedFrames, 50)
        XCTAssertEqual(metricsReceiver.renderingMetrics!.droppedFrames, 49)
        XCTAssertEqual(metricsReceiver.renderingMetrics!.freezeTime.milliseconds, 800 - 16)
        XCTAssertEqual(metricsReceiver.renderingMetrics!.sessionDuration.milliseconds, 800)
        XCTAssertEqual(metricsReceiver.renderingMetrics!.slowFrames, 1)
        XCTAssertEqual(metricsReceiver.renderingMetrics!.frozenFrames, 1)
    }

    private func waitForEvents() {
        let exp = expectation(description: "runloop")
        DispatchQueue.main.asyncAfter(deadline: .now()) {
            exp.fulfill()
        }
        waitForExpectations(timeout: 1, handler: nil)
        PerformanceMonitoring.consumerQueue.sync {}
    }

}

class FramesMeterStub: FramesMeter {
    private weak var receiver: FramesMeterReceiver?

    func subscribe(receiver: FramesMeterReceiver) {
        self.receiver = receiver
    }

    func unsubscribe(receiver: FramesMeterReceiver) {
        XCTAssert(receiver === self.receiver)
        self.receiver = nil
    }

    func report(frameDuration: CFTimeInterval, refreshRateDuration: CFTimeInterval) {
        self.receiver?.frameTicked(frameDuration: frameDuration, refreshRateDuration: refreshRateDuration)
    }

    var isStarted: Bool {
        return receiver != nil
    }

    var didChange: () -> Void = {}
}

class RenderingMetricsReceiverStub: RenderingMetricsReceiver {

    func renderingMetricsReceived(metrics: RenderingMetrics, viewController: UIViewController) {
        renderingCallback(metrics, viewController)
        renderingMetrics = metrics
        lastController = viewController
    }

    func shouldTrack(viewController: UIViewController) -> Bool {
        if viewController is UINavigationController
            || viewController is UITabBarController {
            return false
        }
        return true
    }

    var renderingCallback: (RenderingMetrics, UIViewController) -> Void = { (_, _) in }
    var renderingMetrics: RenderingMetrics?
    var lastController: UIViewController?

}
