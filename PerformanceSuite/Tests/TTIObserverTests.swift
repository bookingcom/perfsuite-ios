//
//  TTIObserverTests.swift
//  PerformanceSuite
//
//  Created by Gleb Tarasov on 06/07/2021.
//

import UIKit
import XCTest

@testable import PerformanceSuite

class TTIObserverTests: XCTestCase {

    override func setUp() {
        super.setUp()

        PerformanceSuite.queue.sync {}
        self.previousQueue = PerformanceSuite.changeQueueForTests(DispatchQueue.main)
    }
    private var previousQueue: DispatchQueue?

    override func tearDown() {
        super.tearDown()
        if let previousQueue = previousQueue {
            PerformanceSuite.changeQueueForTests(previousQueue)
        }
    }

    func testTTIObserverForViewController() throws {
        let vc1 = UIViewController()
        waitForTheNextRunLoop()
        XCTAssertNil(ViewControllerObserverFactory<TTIObserver>.existingObserver(for: vc1))

        try PerformanceSuite.enable(config: [.screenLevelTTI(TTIMetricsReceiverStub())])
        let vc2 = UIViewController()
        waitForTheNextRunLoop()
        XCTAssertNotNil(ViewControllerObserverFactory<TTIObserver>.existingObserver(for: vc2))

        try PerformanceSuite.disable()
        let vc3 = UIViewController()
        waitForTheNextRunLoop()
        XCTAssertNil(ViewControllerObserverFactory<TTIObserver>.existingObserver(for: vc3))

        try PerformanceSuite.enable(config: [])
        let vc4 = UIViewController()
        waitForTheNextRunLoop()
        XCTAssertNil(ViewControllerObserverFactory<TTIObserver>.existingObserver(for: vc4))
        try PerformanceSuite.disable()
    }

    func testTTIMetricViewDidAppearBeforeScreenReady() throws {

        let timeProvider = TimeProviderStub()
        let time = timeProvider.time

        let metricsReceiver = TTIMetricsReceiverStub()
        let observer = TTIObserver(metricsReceiver: metricsReceiver, timeProvider: timeProvider)
        let vc = UIViewController()

        observer.beforeInit(viewController: vc)
        waitForTheNextRunLoop()

        XCTAssertNil(metricsReceiver.ttiMetrics)

        timeProvider.time = time.advanced(by: .milliseconds(9))
        observer.afterViewWillAppear(viewController: vc)
        waitForTheNextRunLoop()

        timeProvider.time = time.advanced(by: .milliseconds(10))
        observer.afterViewDidAppear(viewController: vc)
        waitForTheNextRunLoop()

        XCTAssertNil(metricsReceiver.ttiMetrics)

        timeProvider.time = time.advanced(by: .milliseconds(152))
        observer.screenIsReady()
        waitForTheNextRunLoop()

        PerformanceSuite.consumerQueue.sync {}

        XCTAssertNotNil(metricsReceiver.ttiMetrics)
        XCTAssertEqual(metricsReceiver.ttiMetrics?.tti, .milliseconds(152))
        XCTAssertEqual(metricsReceiver.ttiMetrics?.ttfr, .milliseconds(9))
    }


    func testTTIMetricViewDidAppearAfterScreenReady() throws {

        let timeProvider = TimeProviderStub()
        let time = timeProvider.time

        let metricsReceiver = TTIMetricsReceiverStub()
        let observer = TTIObserver(metricsReceiver: metricsReceiver, timeProvider: timeProvider)
        let vc = UIViewController()

        observer.beforeInit(viewController: vc)
        waitForTheNextRunLoop()

        XCTAssertNil(metricsReceiver.ttiMetrics)

        timeProvider.time = time.advanced(by: .microseconds(4))
        observer.screenIsReady()
        waitForTheNextRunLoop()

        XCTAssertNil(metricsReceiver.ttiMetrics)

        timeProvider.time = time.advanced(by: .microseconds(7))
        observer.afterViewWillAppear(viewController: vc)
        waitForTheNextRunLoop()

        timeProvider.time = time.advanced(by: .microseconds(10))
        observer.afterViewDidAppear(viewController: vc)
        waitForTheNextRunLoop()

        PerformanceSuite.consumerQueue.sync {}

        XCTAssertNotNil(metricsReceiver.ttiMetrics)
        XCTAssertEqual(metricsReceiver.ttiMetrics?.tti, .microseconds(10))
        XCTAssertEqual(metricsReceiver.ttiMetrics?.ttfr, .microseconds(7))
    }

    func testTTIIsDisabledWhenAppGoesToBackground() {
        let timeProvider = TimeProviderStub()
        let time = timeProvider.time

        let metricsReceiver = TTIMetricsReceiverStub()
        let observer = TTIObserver(metricsReceiver: metricsReceiver, timeProvider: timeProvider)
        let vc = UIViewController()

        observer.beforeInit(viewController: vc)

        XCTAssertNil(metricsReceiver.ttiMetrics)

        timeProvider.time = time.advanced(by: .microseconds(4))
        observer.screenIsReady()

        XCTAssertNil(metricsReceiver.ttiMetrics)

        NotificationCenter.default.post(name: UIApplication.willResignActiveNotification, object: nil)

        timeProvider.time = time.advanced(by: .microseconds(10))
        observer.afterViewWillAppear(viewController: vc)
        observer.afterViewDidAppear(viewController: vc)
        PerformanceSuite.consumerQueue.sync {}

        // metrics were not calculated because app went to background
        XCTAssertNil(metricsReceiver.ttiMetrics)
    }

    func testTTIWithCustomCreationTime() {
        let timeProvider = TimeProviderStub()
        let time = timeProvider.time

        let metricsReceiver = TTIMetricsReceiverStub()
        let observer = TTIObserver(metricsReceiver: metricsReceiver, timeProvider: timeProvider)
        let vc = UIViewController()

        TTIObserver.startCustomCreationTime(timeProvider: timeProvider)
        waitForTheNextRunLoop()

        timeProvider.time = time.advanced(by: .milliseconds(200))
        observer.beforeInit(viewController: vc)
        waitForTheNextRunLoop()

        timeProvider.time = time.advanced(by: .milliseconds(214))
        observer.afterViewWillAppear(viewController: vc)
        waitForTheNextRunLoop()

        timeProvider.time = time.advanced(by: .milliseconds(230))
        observer.afterViewDidAppear(viewController: vc)
        waitForTheNextRunLoop()

        timeProvider.time = time.advanced(by: .milliseconds(330))
        observer.screenIsReady()
        waitForTheNextRunLoop()
        PerformanceSuite.consumerQueue.sync {}

        XCTAssertNotNil(metricsReceiver.ttiMetrics)
        XCTAssertEqual(metricsReceiver.ttiMetrics?.tti, .milliseconds(330))
        XCTAssertEqual(metricsReceiver.ttiMetrics?.ttfr, .milliseconds(14))
    }

    func testTTIWithCancelledCustomCreationTime() {
        let timeProvider = TimeProviderStub()
        let time = timeProvider.time

        let metricsReceiver = TTIMetricsReceiverStub()
        let observer = TTIObserver(metricsReceiver: metricsReceiver, timeProvider: timeProvider)
        let vc = UIViewController()
        waitForTheNextRunLoop()

        TTIObserver.startCustomCreationTime(timeProvider: timeProvider)
        TTIObserver.clearCustomCreationTime()
        waitForTheNextRunLoop()

        timeProvider.time = time.advanced(by: .milliseconds(200))
        observer.beforeInit(viewController: vc)
        waitForTheNextRunLoop()

        timeProvider.time = time.advanced(by: .milliseconds(210))
        observer.afterViewWillAppear(viewController: vc)
        waitForTheNextRunLoop()

        timeProvider.time = time.advanced(by: .milliseconds(230))
        observer.afterViewDidAppear(viewController: vc)
        waitForTheNextRunLoop()

        timeProvider.time = time.advanced(by: .milliseconds(330))
        observer.screenIsReady()
        waitForTheNextRunLoop()

        PerformanceSuite.consumerQueue.sync {}

        XCTAssertNotNil(metricsReceiver.ttiMetrics)
        XCTAssertEqual(metricsReceiver.ttiMetrics?.tti, .milliseconds(130))
        XCTAssertEqual(metricsReceiver.ttiMetrics?.ttfr, .milliseconds(10))
    }

    func testTTIWithoutScreenIsReadyCall() {
        let timeProvider = TimeProviderStub()
        let time = timeProvider.time

        let metricsReceiver = TTIMetricsReceiverStub()
        let observer = TTIObserver(metricsReceiver: metricsReceiver, timeProvider: timeProvider)
        let vc = UIViewController()
        waitForTheNextRunLoop()

        observer.beforeInit(viewController: vc)
        waitForTheNextRunLoop()

        XCTAssertNil(metricsReceiver.ttiMetrics)

        timeProvider.time = time.advanced(by: .milliseconds(8))
        observer.afterViewWillAppear(viewController: vc)
        waitForTheNextRunLoop()

        timeProvider.time = time.advanced(by: .milliseconds(10))
        observer.afterViewDidAppear(viewController: vc)
        waitForTheNextRunLoop()

        XCTAssertNil(metricsReceiver.ttiMetrics)

        timeProvider.time = time.advanced(by: .milliseconds(100))
        observer.beforeViewWillDisappear(viewController: vc)
        waitForTheNextRunLoop()

        PerformanceSuite.consumerQueue.sync {}

        XCTAssertNotNil(metricsReceiver.ttiMetrics)
        XCTAssertEqual(metricsReceiver.ttiMetrics?.tti, .milliseconds(10))
        XCTAssertEqual(metricsReceiver.ttiMetrics?.ttfr, .milliseconds(8))
    }

    func testCustomCreationTimeIsForgotten() {
        let timeProvider = TimeProviderStub()
        let time = timeProvider.time

        let metricsReceiver = TTIMetricsReceiverStub()
        let observer = TTIObserver(metricsReceiver: metricsReceiver, timeProvider: timeProvider)
        let vc = UIViewController()
        waitForTheNextRunLoop()

        TTIObserver.startCustomCreationTime(timeProvider: timeProvider)
        waitForTheNextRunLoop()

        timeProvider.time = time.advanced(by: .milliseconds(150))
        observer.beforeInit(viewController: vc)
        waitForTheNextRunLoop()

        timeProvider.time = time.advanced(by: .milliseconds(180))
        observer.afterViewWillAppear(viewController: vc)
        waitForTheNextRunLoop()

        timeProvider.time = time.advanced(by: .milliseconds(200))
        observer.afterViewDidAppear(viewController: vc)
        waitForTheNextRunLoop()

        timeProvider.time = time.advanced(by: .milliseconds(300))
        observer.screenIsReady()
        waitForTheNextRunLoop()

        PerformanceSuite.consumerQueue.sync {}

        XCTAssertEqual(metricsReceiver.ttiMetrics?.tti, .milliseconds(300))
        XCTAssertEqual(metricsReceiver.ttiMetrics?.ttfr, .milliseconds(30))


        let observer2 = TTIObserver(metricsReceiver: metricsReceiver, timeProvider: timeProvider)
        let vc2 = UIViewController()
        waitForTheNextRunLoop()

        timeProvider.time = time.advanced(by: .milliseconds(500))
        observer2.beforeInit(viewController: vc2)
        waitForTheNextRunLoop()

        timeProvider.time = time.advanced(by: .milliseconds(880))
        observer2.afterViewWillAppear(viewController: vc2)
        waitForTheNextRunLoop()

        timeProvider.time = time.advanced(by: .milliseconds(900))
        observer2.afterViewDidAppear(viewController: vc2)
        waitForTheNextRunLoop()

        timeProvider.time = time.advanced(by: .milliseconds(1300))
        observer2.screenIsReady()
        waitForTheNextRunLoop()

        PerformanceSuite.consumerQueue.sync {}

        XCTAssertEqual(metricsReceiver.ttiMetrics?.tti, .milliseconds(800))
        XCTAssertEqual(metricsReceiver.ttiMetrics?.ttfr, .milliseconds(380))
    }

    func testCustomCreationTimeIsCleared() {
        let timeProvider = TimeProviderStub()
        let time = timeProvider.time

        let metricsReceiver = TTIMetricsReceiverStub()

        TTIObserver.startCustomCreationTime(timeProvider: timeProvider)

        TTIObserver.clearCustomCreationTime()

        XCTAssertNil(metricsReceiver.ttiMetrics)

        let observer = TTIObserver(metricsReceiver: metricsReceiver, timeProvider: timeProvider)
        let vc = UIViewController()
        waitForTheNextRunLoop()

        timeProvider.time = time.advanced(by: .milliseconds(500))
        observer.beforeInit(viewController: vc)
        waitForTheNextRunLoop()

        timeProvider.time = time.advanced(by: .milliseconds(600))
        observer.afterViewWillAppear(viewController: vc)
        waitForTheNextRunLoop()

        timeProvider.time = time.advanced(by: .milliseconds(900))
        observer.afterViewDidAppear(viewController: vc)
        waitForTheNextRunLoop()

        timeProvider.time = time.advanced(by: .milliseconds(1300))
        observer.screenIsReady()
        waitForTheNextRunLoop()

        PerformanceSuite.consumerQueue.sync {}

        XCTAssertEqual(metricsReceiver.ttiMetrics?.tti, .milliseconds(800))
        XCTAssertEqual(metricsReceiver.ttiMetrics?.ttfr, .milliseconds(100))
    }

    func testScreenIsReadyCallBeforeTTI() {
        // There can be the case, when we call `perf_screenIsReady` for the second screen while TTI for the first screen is not calculated
        // We should test that we won't take customCreationTime for the first screen TTI calculation

        let timeProvider = TimeProviderStub()
        let time = timeProvider.time

        let metricsReceiver = TTIMetricsReceiverStub()
        let observer1 = TTIObserver(metricsReceiver: metricsReceiver, timeProvider: timeProvider)
        let vc1 = UIViewController()

        let observer2 = TTIObserver(metricsReceiver: metricsReceiver, timeProvider: timeProvider)
        let vc2 = UIViewController()

        timeProvider.time = time.advanced(by: .milliseconds(500))
        observer1.beforeInit(viewController: vc1)
        waitForTheNextRunLoop()

        timeProvider.time = time.advanced(by: .milliseconds(600))
        observer1.afterViewWillAppear(viewController: vc1)
        waitForTheNextRunLoop()

        timeProvider.time = time.advanced(by: .milliseconds(900))
        observer1.afterViewDidAppear(viewController: vc1)
        waitForTheNextRunLoop()

        timeProvider.time = time.advanced(by: .milliseconds(1300))
        TTIObserver.startCustomCreationTime(timeProvider: timeProvider)
        waitForTheNextRunLoop()

        timeProvider.time = time.advanced(by: .milliseconds(1400))
        observer2.beforeInit(viewController: vc2)
        waitForTheNextRunLoop()

        timeProvider.time = time.advanced(by: .milliseconds(1500))
        observer1.beforeViewWillDisappear(viewController: vc1)
        waitForTheNextRunLoop()

        PerformanceSuite.consumerQueue.sync {}

        XCTAssertEqual(metricsReceiver.ttiMetrics?.tti, .milliseconds(400))  // between 500 and 900
        XCTAssertEqual(metricsReceiver.ttiMetrics?.ttfr, .milliseconds(100))  // between 500 and 600
        XCTAssert(metricsReceiver.lastController === vc1)

        timeProvider.time = time.advanced(by: .milliseconds(1600))
        observer2.afterViewWillAppear(viewController: vc2)
        waitForTheNextRunLoop()

        timeProvider.time = time.advanced(by: .milliseconds(2000))
        observer2.afterViewDidAppear(viewController: vc2)
        waitForTheNextRunLoop()

        timeProvider.time = time.advanced(by: .milliseconds(2600))
        observer2.beforeViewWillDisappear(viewController: vc2)
        waitForTheNextRunLoop()

        PerformanceSuite.consumerQueue.sync {}

        XCTAssertEqual(metricsReceiver.ttiMetrics?.tti, .milliseconds(700))  // between 1300 and 2000
        XCTAssertEqual(metricsReceiver.ttiMetrics?.ttfr, .milliseconds(200))  // between 1400 and 1600
        XCTAssert(metricsReceiver.lastController === vc2)
    }

    func testCustomCreationAfterViewWillAppear() {
        // There can be the case, when user called `perf_screenIsBeingCreated` after `viewWillAppear`.
        // We should consider this `customCreationTime` for the second screen, not for the first one.

        let timeProvider = TimeProviderStub()
        let time = timeProvider.time

        let metricsReceiver = TTIMetricsReceiverStub()
        let observer = TTIObserver(metricsReceiver: metricsReceiver, timeProvider: timeProvider)
        let vc = UIViewController()
        waitForTheNextRunLoop()

        timeProvider.time = time.advanced(by: .milliseconds(100))
        observer.beforeInit(viewController: vc)
        waitForTheNextRunLoop()

        timeProvider.time = time.advanced(by: .milliseconds(400))
        observer.afterViewWillAppear(viewController: vc)
        waitForTheNextRunLoop()

        timeProvider.time = time.advanced(by: .milliseconds(600))
        TTIObserver.startCustomCreationTime(timeProvider: timeProvider)
        waitForTheNextRunLoop()

        timeProvider.time = time.advanced(by: .milliseconds(900))
        observer.afterViewDidAppear(viewController: vc)
        waitForTheNextRunLoop()

        timeProvider.time = time.advanced(by: .milliseconds(2000))
        observer.beforeViewWillDisappear(viewController: vc)
        waitForTheNextRunLoop()

        PerformanceSuite.consumerQueue.sync {}

        XCTAssertEqual(metricsReceiver.ttiMetrics?.tti, .milliseconds(800))  // between 100 and 900
        XCTAssertEqual(metricsReceiver.ttiMetrics?.ttfr, .milliseconds(300))  // between 100 and 400
        
        // prepare for the next test
        TTIObserver.clearCustomCreationTime()
        waitForTheNextRunLoop()
    }

    func test2ViewWillAppearCallsWithoutViewDidAppear() {
        // Testing rare case, when viewDidAppear is not called for the VC, after next VC is shown instantly without animation.
        // In this case we should just ignore TTI for the first VC.
        let timeProvider = TimeProviderStub()
        let time = timeProvider.time

        let metricsReceiver = TTIMetricsReceiverStub()
        let observer1 = TTIObserver(metricsReceiver: metricsReceiver, timeProvider: timeProvider)
        let vc1 = UIViewController()

        let observer2 = TTIObserver(metricsReceiver: metricsReceiver, timeProvider: timeProvider)
        let vc2 = UIViewController()

        timeProvider.time = time.advanced(by: .milliseconds(500))
        observer1.beforeInit(viewController: vc1)
        observer2.beforeInit(viewController: vc2)
        waitForTheNextRunLoop()

        timeProvider.time = time.advanced(by: .milliseconds(600))
        observer1.afterViewWillAppear(viewController: vc1)
        observer2.afterViewWillAppear(viewController: vc2)
        waitForTheNextRunLoop()

        timeProvider.time = time.advanced(by: .milliseconds(1300))
        observer2.afterViewDidAppear(viewController: vc2)
        waitForTheNextRunLoop()

        timeProvider.time = time.advanced(by: .milliseconds(10000))
        observer2.beforeViewWillDisappear(viewController: vc2)
        waitForTheNextRunLoop()

        timeProvider.time = time.advanced(by: .milliseconds(10100))
        observer1.afterViewWillAppear(viewController: vc1)
        waitForTheNextRunLoop()

        PerformanceSuite.consumerQueue.sync {}

        XCTAssertEqual(metricsReceiver.ttiMetrics?.tti, .milliseconds(800))  // between 500 and 1300
        XCTAssertEqual(metricsReceiver.ttiMetrics?.ttfr, .milliseconds(100))  // between 500 and 600
        XCTAssert(metricsReceiver.lastController === vc2)

        metricsReceiver.lastController = nil
        metricsReceiver.ttiMetrics = nil

        timeProvider.time = time.advanced(by: .milliseconds(11000))
        observer1.afterViewDidAppear(viewController: vc1)

        timeProvider.time = time.advanced(by: .milliseconds(15000))
        observer1.beforeViewWillDisappear(viewController: vc1)
        PerformanceSuite.consumerQueue.sync {}

        // TTI shouldn't be sent
        XCTAssertNil(metricsReceiver.lastController)
        XCTAssertNil(metricsReceiver.ttiMetrics)
    }

    private func waitForTheNextRunLoop() {
        let exp = expectation(description: "runloop")
        DispatchQueue.main.asyncAfter(deadline: .now()) {
            exp.fulfill()
        }
        waitForExpectations(timeout: 1, handler: nil)
    }
}

class TimeProviderStub: TimeProvider {
    var time = DispatchTime(uptimeNanoseconds: 1_000_000_000)
    func now() -> DispatchTime {
        return time
    }
}

class TTIMetricsReceiverStub: TTIMetricsReceiver {
    func ttiMetricsReceived(metrics: TTIMetrics, viewController: UIViewController) {
        ttiCallback(metrics, viewController)
        ttiMetrics = metrics
        lastController = viewController
    }

    func shouldTrack(viewController: UIViewController) -> Bool {
        if viewController is UINavigationController
            || viewController is UITabBarController
        {
            return false
        }
        return true
    }

    var ttiCallback: (TTIMetrics, UIViewController) -> Void = { (_, _) in }
    var ttiMetrics: TTIMetrics?
    var lastController: UIViewController?
}
