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
        let observer = RenderingObserver(screen: UIViewController(), metricsReceiver: metricsReceiver, framesMeter: framesMeter)

        let vc = UIViewController()

        waitForEvents()

        // should be ignored
        framesMeter.report(frameDuration: 160, refreshRateDuration: 0.016)

        observer.beforeInit()
        waitForEvents()

        // should be ignored
        framesMeter.report(frameDuration: 1600, refreshRateDuration: 0.016)

        observer.afterViewWillAppear()
        waitForEvents()

        // should be ignored
        framesMeter.report(frameDuration: 16000, refreshRateDuration: 0.016)

        observer.afterViewDidAppear()
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

        observer.beforeViewWillDisappear()
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
        let observer = RenderingObserver(screen: UIViewController(), metricsReceiver: metricsReceiver, framesMeter: framesMeter)

        let vc = UIViewController()

        observer.beforeInit()
        observer.afterViewWillAppear()
        observer.afterViewDidAppear()
        waitForEvents()

        // 9 dropped frames, 10 expected frames, 1 slow, 0 frozen
        framesMeter.report(frameDuration: 0.16, refreshRateDuration: 0.016)

        observer.beforeViewWillDisappear()
        waitForEvents()

        XCTAssertEqual(metricsReceiver.renderingMetrics!.expectedFrames, 10)
        XCTAssertEqual(metricsReceiver.renderingMetrics!.droppedFrames, 9)
        XCTAssertEqual(metricsReceiver.renderingMetrics!.freezeTime.milliseconds, 160 - 16)
        XCTAssertEqual(metricsReceiver.renderingMetrics!.sessionDuration.milliseconds, 160)
        XCTAssertEqual(metricsReceiver.renderingMetrics!.slowFrames, 1)
        XCTAssertEqual(metricsReceiver.renderingMetrics!.frozenFrames, 0)
        metricsReceiver.renderingMetrics = nil

        observer.afterViewWillAppear()
        observer.afterViewDidAppear()
        waitForEvents()

        // 49 dropped frames, 50 expected frames, 1 slow, 1 frozen
        framesMeter.report(frameDuration: 0.8, refreshRateDuration: 0.016)

        observer.beforeViewWillDisappear()
        waitForEvents()

        XCTAssertEqual(metricsReceiver.renderingMetrics!.expectedFrames, 50)
        XCTAssertEqual(metricsReceiver.renderingMetrics!.droppedFrames, 49)
        XCTAssertEqual(metricsReceiver.renderingMetrics!.freezeTime.milliseconds, 800 - 16)
        XCTAssertEqual(metricsReceiver.renderingMetrics!.sessionDuration.milliseconds, 800)
        XCTAssertEqual(metricsReceiver.renderingMetrics!.slowFrames, 1)
        XCTAssertEqual(metricsReceiver.renderingMetrics!.frozenFrames, 1)
    }

    func testEmptySessionDoesNotDispatchToPhase1ReceiverDespiteAnchoredZero() {
        // Regression guard for the → legacy contract: a session where
        // `frameTicked` never ran (screen instantly dismissed before any frame)
        // must NOT trigger `renderingMetricsReceived` for legacy receivers.
        // This was almost lost when `RenderingObserver.afterViewDidAppear` was
        // changed to seed `self.metrics` with `.zero(sessionStarted: …)` instead
        // of bare `.zero` — the seeded value is `!= .zero` by Equatable, so a
        // naive `metrics != .zero` guard would dispatch every empty session.
        let metricsReceiver = RenderingMetricsReceiverStub()
        let framesMeter = FramesMeterStub()
        let observer = RenderingObserver(screen: UIViewController(), metricsReceiver: metricsReceiver, framesMeter: framesMeter)

        observer.beforeInit()
        observer.afterViewWillAppear()
        observer.afterViewDidAppear()
        waitForEvents()
        // No frames reported between viewDidAppear and viewWillDisappear.
        observer.beforeViewWillDisappear()
        waitForEvents()

        XCTAssertNil(
            metricsReceiver.renderingMetrics,
            "legacy receiver: empty session must not dispatch (legacy behaviour preserved)"
        )
    }

    func testEmptySessionWithLiveReceiverDispatchesSoMeasurementCanFinalise() {
        // Mirror of the previous test but with a live receiver that returns a
        // non-nil `MeasurementHandle` from `screenRenderingStarted`.
        // Even with no frames, the `screenRenderingEnded` callback must fire so
        // the live measurement can be finalised — an empty foreground session is
        // signal for the live-measurement lane.
        let metricsReceiver = LiveRenderingMetricsReceiverStub()
        let framesMeter = FramesMeterStub()
        let observer = RenderingObserver(screen: UIViewController(), metricsReceiver: metricsReceiver, framesMeter: framesMeter)

        observer.beforeInit()
        observer.afterViewWillAppear()
        observer.afterViewDidAppear()
        waitForEvents()
        observer.beforeViewWillDisappear()
        waitForEvents()

        XCTAssertEqual(
            metricsReceiver.endedCalls.count, 1,
            "Live receiver: empty session must still dispatch ended() so the measurement can finalise"
        )
        XCTAssertNotNil(
            metricsReceiver.endedCalls.first?.context,
            "The same context returned from started() must round-trip back to ended()"
        )
    }

    func testSyncPushPopProcessesDisappearAfterDidAppearCompletesItsSetup() {
        // Sync push-pop: in the swizzler, didAppear's reaction is `main.async` but
        // willDisappear is direct, so with no runloop tick willDisappear's PM closure
        // enqueues BEFORE didAppear's. The observer must park the disappear, set up via
        // didAppear, then end cleanly — not leave an orphan cancelled measurement at deinit.
        let metricsReceiver = LiveRenderingMetricsReceiverStub()
        let framesMeter = FramesMeterStub()
        let observer = RenderingObserver(screen: UIViewController(), metricsReceiver: metricsReceiver, framesMeter: framesMeter)

        observer.beforeInit()
        observer.afterViewWillAppear()
        // Inverted order — willDisappear's PM closure enqueues first.
        observer.beforeViewWillDisappear()
        observer.afterViewDidAppear()
        waitForEvents()

        XCTAssertEqual(
            metricsReceiver.startedContexts.count, 1,
            "didAppear's setup must run and start the live measurement even when willDisappear queued first"
        )
        XCTAssertEqual(
            metricsReceiver.endedCalls.count, 1,
            "Disappear must be processed once didAppear's setup completes — measurement ends cleanly, not via deinit cancel"
        )
        XCTAssertEqual(
            metricsReceiver.startedContexts.first?.cancelCount, 0,
            "Measurement must end via the live ended path, NOT via cancel() (which is the orphan-at-deinit failure mode)"
        )
        XCTAssertFalse(
            framesMeter.isStarted,
            "FramesMeter must be unsubscribed by the deferred processDisappear — pre-fix this would leak a subscription"
        )
        XCTAssertNotNil(
            metricsReceiver.endedCalls.first?.context,
            "The live context started in afterViewDidAppear must round-trip back to ended"
        )
    }

    func testReusedInstanceSyncPushPopEndsEachSessionWithItsOwnMeasurement() {
        // K1 regression: a reused VC instance hitting a SECOND inverted sync push-pop. Pre-fix
        // `didAppearProcessed` stayed latched true from cycle 1, so cycle 2's disappear ran before
        // its re-appear setup — ending with a stale/nil context and orphaning the freshly-opened
        // measurement. Each session must instead open and cleanly end its own live measurement.
        let metricsReceiver = LiveRenderingMetricsReceiverStub()
        let framesMeter = FramesMeterStub()
        let observer = RenderingObserver(screen: UIViewController(), metricsReceiver: metricsReceiver, framesMeter: framesMeter)

        observer.beforeInit()

        // Cycle 1 — inverted order (willDisappear's PM closure enqueues before didAppear's).
        observer.afterViewWillAppear()
        observer.beforeViewWillDisappear()
        observer.afterViewDidAppear()
        waitForEvents()

        // Cycle 2 — same instance, inverted again.
        observer.afterViewWillAppear()
        observer.beforeViewWillDisappear()
        observer.afterViewDidAppear()
        waitForEvents()

        XCTAssertEqual(metricsReceiver.startedContexts.count, 2, "Each foreground session opens its own live measurement")
        XCTAssertEqual(
            metricsReceiver.endedCalls.filter { $0.context != nil }.count, 2,
            "Both sessions end via their own live context — pre-fix the 2nd measurement is orphaned (ended with nil/stale context)"
        )
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

    func renderingMetricsReceived(metrics: RenderingMetrics, screen viewController: UIViewController) {
        renderingCallback(metrics, viewController)
        renderingMetrics = metrics
        lastController = viewController
    }

    func screenIdentifier(for viewController: UIViewController) -> UIViewController? {
        if viewController is UINavigationController
            || viewController is UITabBarController {
            return nil
        }
        return viewController
    }

    var renderingCallback: (RenderingMetrics, UIViewController) -> Void = { (_, _) in }
    var renderingMetrics: RenderingMetrics?
    var lastController: UIViewController?

}

/// Live-style receiver for the live-measurement dispatch tests. Returns a non-nil context
/// from `screenRenderingStarted` so the observer holds it across the session
/// and routes it back through `screenRenderingEnded` — including for the
/// empty-session case.
final class LiveRenderingMetricsReceiverStub: LiveRenderingMetricsReceiver {

    final class StubContext: MeasurementHandle {
        var cancelCount = 0
        func cancel() { cancelCount += 1 }
    }

    struct EndedCall {
        let metrics: RenderingMetrics
        let screen: UIViewController
        let context: (any MeasurementHandle)?
    }

    var startedContexts: [StubContext] = []
    var endedCalls: [EndedCall] = []

    func screenIdentifier(for viewController: UIViewController) -> UIViewController? {
        return viewController
    }

    func renderingMetricsReceived(metrics: RenderingMetrics, screen: UIViewController) {
        // Live receiver always resolves to `screenRenderingEnded`; the completed
        // callback must never fire for it.
        XCTFail("renderingMetricsReceived should not fire for a live receiver")
    }

    func screenRenderingStarted(screen: UIViewController, sessionStarted: Date) -> (any MeasurementHandle)? {
        let ctx = StubContext()
        startedContexts.append(ctx)
        return ctx
    }

    func screenRenderingEnded(metrics: RenderingMetrics, screen: UIViewController, context: (any MeasurementHandle)?) {
        endedCalls.append(EndedCall(metrics: metrics, screen: screen, context: context))
    }
}
