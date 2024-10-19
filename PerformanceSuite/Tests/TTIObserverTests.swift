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

    func testTTIObserverForViewController() throws {
        let vc1 = MyViewController()
        waitForTheNextRunLoop()
        XCTAssertNil(ViewControllerObserverFactoryHelper.existingObserver(for: vc1, identifier: TTIObserverHelper.identifier))

        try PerformanceMonitoring.enable(config: [.screenLevelTTI(TTIMetricsReceiverStub())])
        let vc2 = MyViewController()
        waitForTheNextRunLoop()
        XCTAssertNotNil(ViewControllerObserverFactoryHelper.existingObserver(for: vc2, identifier: TTIObserverHelper.identifier))

        try PerformanceMonitoring.disable()
        let vc3 = MyViewController()
        waitForTheNextRunLoop()
        XCTAssertNil(ViewControllerObserverFactoryHelper.existingObserver(for: vc3, identifier: TTIObserverHelper.identifier))

        try PerformanceMonitoring.enable(config: [])
        let vc4 = MyViewController()
        waitForTheNextRunLoop()
        XCTAssertNil(ViewControllerObserverFactoryHelper.existingObserver(for: vc4, identifier: TTIObserverHelper.identifier))
        try PerformanceMonitoring.disable()
    }

    func testTTIMetricViewDidAppearBeforeScreenReady() throws {

        let timeProvider = TimeProviderStub()
        let time = timeProvider.time

        let metricsReceiver = TTIMetricsReceiverStub()
        let observer = TTIObserver(screen: UIViewController(), metricsReceiver: metricsReceiver, timeProvider: timeProvider)

        observer.beforeInit()
        waitForTheNextRunLoop()

        XCTAssertNil(metricsReceiver.ttiMetrics)

        timeProvider.time = time.advanced(by: .milliseconds(9))
        observer.afterViewWillAppear()
        waitForTheNextRunLoop()

        timeProvider.time = time.advanced(by: .milliseconds(10))
        observer.afterViewDidAppear()
        waitForTheNextRunLoop()

        XCTAssertNil(metricsReceiver.ttiMetrics)

        timeProvider.time = time.advanced(by: .milliseconds(152))
        observer.screenIsReady()
        waitForTheNextRunLoop()

        PerformanceMonitoring.consumerQueue.sync {}

        XCTAssertNotNil(metricsReceiver.ttiMetrics)
        XCTAssertEqual(metricsReceiver.ttiMetrics?.tti, .milliseconds(152))
        XCTAssertEqual(metricsReceiver.ttiMetrics?.ttfr, .milliseconds(9))
    }


    func testTTIMetricViewDidAppearAfterScreenReady() throws {

        let timeProvider = TimeProviderStub()
        let time = timeProvider.time

        let metricsReceiver = TTIMetricsReceiverStub()
        let observer = TTIObserver(screen: UIViewController(), metricsReceiver: metricsReceiver, timeProvider: timeProvider)

        observer.beforeInit()
        waitForTheNextRunLoop()

        XCTAssertNil(metricsReceiver.ttiMetrics)

        timeProvider.time = time.advanced(by: .microseconds(4))
        observer.screenIsReady()
        waitForTheNextRunLoop()

        XCTAssertNil(metricsReceiver.ttiMetrics)

        timeProvider.time = time.advanced(by: .microseconds(7))
        observer.afterViewWillAppear()
        waitForTheNextRunLoop()

        timeProvider.time = time.advanced(by: .microseconds(10))
        observer.afterViewDidAppear()
        waitForTheNextRunLoop()

        PerformanceMonitoring.consumerQueue.sync {}

        XCTAssertNotNil(metricsReceiver.ttiMetrics)
        XCTAssertEqual(metricsReceiver.ttiMetrics?.tti, .microseconds(10))
        XCTAssertEqual(metricsReceiver.ttiMetrics?.ttfr, .microseconds(7))
    }

    func testTTIIsDisabledWhenAppGoesToBackground() {
        let timeProvider = TimeProviderStub()
        let time = timeProvider.time

        let metricsReceiver = TTIMetricsReceiverStub()
        let observer = TTIObserver(screen: UIViewController(), metricsReceiver: metricsReceiver, timeProvider: timeProvider)

        observer.beforeInit()

        XCTAssertNil(metricsReceiver.ttiMetrics)

        timeProvider.time = time.advanced(by: .microseconds(4))
        observer.screenIsReady()

        XCTAssertNil(metricsReceiver.ttiMetrics)

        NotificationCenter.default.post(name: UIApplication.willResignActiveNotification, object: nil)

        timeProvider.time = time.advanced(by: .microseconds(10))
        observer.afterViewWillAppear()
        observer.afterViewDidAppear()
        PerformanceMonitoring.consumerQueue.sync {}

        // metrics were not calculated because app went to background
        XCTAssertNil(metricsReceiver.ttiMetrics)
    }

    func testTTIWithCustomCreationTime() {
        let timeProvider = TimeProviderStub()
        let time = timeProvider.time

        let metricsReceiver = TTIMetricsReceiverStub()
        let observer = TTIObserver(screen: UIViewController(), metricsReceiver: metricsReceiver, timeProvider: timeProvider)

        TTIObserverHelper.startCustomCreationTime(timeProvider: timeProvider)
        waitForTheNextRunLoop()

        timeProvider.time = time.advanced(by: .milliseconds(200))
        observer.beforeInit()
        waitForTheNextRunLoop()

        timeProvider.time = time.advanced(by: .milliseconds(214))
        observer.afterViewWillAppear()
        waitForTheNextRunLoop()

        timeProvider.time = time.advanced(by: .milliseconds(230))
        observer.afterViewDidAppear()
        waitForTheNextRunLoop()

        timeProvider.time = time.advanced(by: .milliseconds(330))
        observer.screenIsReady()
        waitForTheNextRunLoop()
        PerformanceMonitoring.consumerQueue.sync {}

        XCTAssertNotNil(metricsReceiver.ttiMetrics)
        XCTAssertEqual(metricsReceiver.ttiMetrics?.tti, .milliseconds(330))
        XCTAssertEqual(metricsReceiver.ttiMetrics?.ttfr, .milliseconds(14))
    }

    func testTTIWithCancelledCustomCreationTime() {
        let timeProvider = TimeProviderStub()
        let time = timeProvider.time

        let metricsReceiver = TTIMetricsReceiverStub()
        let observer = TTIObserver(screen: UIViewController(), metricsReceiver: metricsReceiver, timeProvider: timeProvider)
        waitForTheNextRunLoop()

        TTIObserverHelper.startCustomCreationTime(timeProvider: timeProvider)
        TTIObserverHelper.clearCustomCreationTime()
        waitForTheNextRunLoop()

        timeProvider.time = time.advanced(by: .milliseconds(200))
        observer.beforeInit()
        waitForTheNextRunLoop()

        timeProvider.time = time.advanced(by: .milliseconds(210))
        observer.afterViewWillAppear()
        waitForTheNextRunLoop()

        timeProvider.time = time.advanced(by: .milliseconds(230))
        observer.afterViewDidAppear()
        waitForTheNextRunLoop()

        timeProvider.time = time.advanced(by: .milliseconds(330))
        observer.screenIsReady()
        waitForTheNextRunLoop()

        PerformanceMonitoring.consumerQueue.sync {}

        XCTAssertNotNil(metricsReceiver.ttiMetrics)
        XCTAssertEqual(metricsReceiver.ttiMetrics?.tti, .milliseconds(130))
        XCTAssertEqual(metricsReceiver.ttiMetrics?.ttfr, .milliseconds(10))

        XCTAssertEqual(metricsReceiver.ttiMetrics?.description, "tti: 130 ms, ttfr: 10 ms")
    }

    func testTTIWithoutScreenIsReadyCall() {
        let timeProvider = TimeProviderStub()
        let time = timeProvider.time

        let metricsReceiver = TTIMetricsReceiverStub()
        let observer = TTIObserver(screen: UIViewController(), metricsReceiver: metricsReceiver, timeProvider: timeProvider)
        waitForTheNextRunLoop()

        observer.beforeInit()
        waitForTheNextRunLoop()

        XCTAssertNil(metricsReceiver.ttiMetrics)

        timeProvider.time = time.advanced(by: .milliseconds(8))
        observer.afterViewWillAppear()
        waitForTheNextRunLoop()

        timeProvider.time = time.advanced(by: .milliseconds(10))
        observer.afterViewDidAppear()
        waitForTheNextRunLoop()

        XCTAssertNil(metricsReceiver.ttiMetrics)

        timeProvider.time = time.advanced(by: .milliseconds(100))
        observer.beforeViewWillDisappear()
        waitForTheNextRunLoop()

        PerformanceMonitoring.consumerQueue.sync {}

        XCTAssertNotNil(metricsReceiver.ttiMetrics)
        XCTAssertEqual(metricsReceiver.ttiMetrics?.tti, .milliseconds(10))
        XCTAssertEqual(metricsReceiver.ttiMetrics?.ttfr, .milliseconds(8))
    }

    func testCustomCreationTimeIsForgotten() {
        let timeProvider = TimeProviderStub()
        let time = timeProvider.time

        let metricsReceiver = TTIMetricsReceiverStub()
        let observer = TTIObserver(screen: UIViewController(), metricsReceiver: metricsReceiver, timeProvider: timeProvider)
        waitForTheNextRunLoop()

        TTIObserverHelper.startCustomCreationTime(timeProvider: timeProvider)
        waitForTheNextRunLoop()

        timeProvider.time = time.advanced(by: .milliseconds(150))
        observer.beforeInit()
        waitForTheNextRunLoop()

        timeProvider.time = time.advanced(by: .milliseconds(180))
        observer.afterViewWillAppear()
        waitForTheNextRunLoop()

        timeProvider.time = time.advanced(by: .milliseconds(200))
        observer.afterViewDidAppear()
        waitForTheNextRunLoop()

        timeProvider.time = time.advanced(by: .milliseconds(300))
        observer.screenIsReady()
        waitForTheNextRunLoop()

        PerformanceMonitoring.consumerQueue.sync {}

        XCTAssertEqual(metricsReceiver.ttiMetrics?.tti, .milliseconds(300))
        XCTAssertEqual(metricsReceiver.ttiMetrics?.ttfr, .milliseconds(30))


        let observer2 = TTIObserver(screen: UIViewController(), metricsReceiver: metricsReceiver, timeProvider: timeProvider)
        let vc2 = UIViewController()
        waitForTheNextRunLoop()

        timeProvider.time = time.advanced(by: .milliseconds(500))
        observer2.beforeInit()
        waitForTheNextRunLoop()

        timeProvider.time = time.advanced(by: .milliseconds(880))
        observer2.afterViewWillAppear()
        waitForTheNextRunLoop()

        timeProvider.time = time.advanced(by: .milliseconds(900))
        observer2.afterViewDidAppear()
        waitForTheNextRunLoop()

        timeProvider.time = time.advanced(by: .milliseconds(1300))
        observer2.screenIsReady()
        waitForTheNextRunLoop()

        PerformanceMonitoring.consumerQueue.sync {}

        XCTAssertEqual(metricsReceiver.ttiMetrics?.tti, .milliseconds(800))
        XCTAssertEqual(metricsReceiver.ttiMetrics?.ttfr, .milliseconds(380))
    }

    func testCustomCreationTimeIsCleared() {
        let timeProvider = TimeProviderStub()
        let time = timeProvider.time

        let metricsReceiver = TTIMetricsReceiverStub()

        TTIObserverHelper.startCustomCreationTime(timeProvider: timeProvider)

        TTIObserverHelper.clearCustomCreationTime()

        XCTAssertNil(metricsReceiver.ttiMetrics)

        let observer = TTIObserver(screen: UIViewController(), metricsReceiver: metricsReceiver, timeProvider: timeProvider)
        waitForTheNextRunLoop()

        timeProvider.time = time.advanced(by: .milliseconds(500))
        observer.beforeInit()
        waitForTheNextRunLoop()

        timeProvider.time = time.advanced(by: .milliseconds(600))
        observer.afterViewWillAppear()
        waitForTheNextRunLoop()

        timeProvider.time = time.advanced(by: .milliseconds(900))
        observer.afterViewDidAppear()
        waitForTheNextRunLoop()

        timeProvider.time = time.advanced(by: .milliseconds(1300))
        observer.screenIsReady()
        waitForTheNextRunLoop()

        PerformanceMonitoring.consumerQueue.sync {}

        XCTAssertEqual(metricsReceiver.ttiMetrics?.tti, .milliseconds(800))
        XCTAssertEqual(metricsReceiver.ttiMetrics?.ttfr, .milliseconds(100))
    }

    func testScreenIsReadyCallBeforeTTI() {
        // There can be the case, when we call `screenIsReady` for the second screen while TTI for the first screen is not calculated
        // We should test that we won't take customCreationTime for the first screen TTI calculation

        let timeProvider = TimeProviderStub()
        let time = timeProvider.time

        let metricsReceiver = TTIMetricsReceiverStub()
        let vc1 = UIViewController()
        let observer1 = TTIObserver(screen: vc1, metricsReceiver: metricsReceiver, timeProvider: timeProvider)

        let vc2 = UIViewController()
        let observer2 = TTIObserver(screen: vc2, metricsReceiver: metricsReceiver, timeProvider: timeProvider)

        timeProvider.time = time.advanced(by: .milliseconds(500))
        observer1.beforeInit()
        waitForTheNextRunLoop()

        timeProvider.time = time.advanced(by: .milliseconds(600))
        observer1.afterViewWillAppear()
        waitForTheNextRunLoop()

        timeProvider.time = time.advanced(by: .milliseconds(900))
        observer1.afterViewDidAppear()
        waitForTheNextRunLoop()

        timeProvider.time = time.advanced(by: .milliseconds(1300))
        TTIObserverHelper.startCustomCreationTime(timeProvider: timeProvider)
        waitForTheNextRunLoop()

        timeProvider.time = time.advanced(by: .milliseconds(1400))
        observer2.beforeInit()
        waitForTheNextRunLoop()

        timeProvider.time = time.advanced(by: .milliseconds(1500))
        observer1.beforeViewWillDisappear()
        waitForTheNextRunLoop()

        PerformanceMonitoring.consumerQueue.sync {}

        XCTAssertEqual(metricsReceiver.ttiMetrics?.tti, .milliseconds(400))  // between 500 and 900
        XCTAssertEqual(metricsReceiver.ttiMetrics?.ttfr, .milliseconds(100))  // between 500 and 600
        XCTAssertEqual(metricsReceiver.lastController, vc1)

        timeProvider.time = time.advanced(by: .milliseconds(1600))
        observer2.afterViewWillAppear()
        waitForTheNextRunLoop()

        timeProvider.time = time.advanced(by: .milliseconds(2000))
        observer2.afterViewDidAppear()
        waitForTheNextRunLoop()

        timeProvider.time = time.advanced(by: .milliseconds(2600))
        observer2.beforeViewWillDisappear()
        waitForTheNextRunLoop()

        PerformanceMonitoring.consumerQueue.sync {}

        XCTAssertEqual(metricsReceiver.ttiMetrics?.tti, .milliseconds(700))  // between 1300 and 2000
        XCTAssertEqual(metricsReceiver.ttiMetrics?.ttfr, .milliseconds(200))  // between 1400 and 1600
        XCTAssertEqual(metricsReceiver.lastController, vc2)
    }

    func testCustomCreationAfterViewWillAppear() {
        // There can be the case, when user called `screenIsBeingCreated` after `viewWillAppear`.
        // We should consider this `customCreationTime` for the second screen, not for the first one.

        let timeProvider = TimeProviderStub()
        let time = timeProvider.time

        let metricsReceiver = TTIMetricsReceiverStub()
        let observer = TTIObserver(screen: UIViewController(), metricsReceiver: metricsReceiver, timeProvider: timeProvider)
        waitForTheNextRunLoop()

        timeProvider.time = time.advanced(by: .milliseconds(100))
        observer.beforeInit()
        waitForTheNextRunLoop()

        timeProvider.time = time.advanced(by: .milliseconds(400))
        observer.afterViewWillAppear()
        waitForTheNextRunLoop()

        timeProvider.time = time.advanced(by: .milliseconds(600))
        TTIObserverHelper.startCustomCreationTime(timeProvider: timeProvider)
        waitForTheNextRunLoop()

        timeProvider.time = time.advanced(by: .milliseconds(900))
        observer.afterViewDidAppear()
        waitForTheNextRunLoop()

        timeProvider.time = time.advanced(by: .milliseconds(2000))
        observer.beforeViewWillDisappear()
        waitForTheNextRunLoop()

        PerformanceMonitoring.consumerQueue.sync {}

        XCTAssertEqual(metricsReceiver.ttiMetrics?.tti, .milliseconds(800))  // between 100 and 900
        XCTAssertEqual(metricsReceiver.ttiMetrics?.ttfr, .milliseconds(300))  // between 100 and 400

        // prepare for the next test
        TTIObserverHelper.clearCustomCreationTime()
        waitForTheNextRunLoop()
    }

    func test2ViewWillAppearCallsWithoutViewDidAppear() {
        // Testing rare case, when viewDidAppear is not called for the VC, after next VC is shown instantly without animation.
        // In this case we should just ignore TTI for the first VC.
        let timeProvider = TimeProviderStub()
        let time = timeProvider.time

        let metricsReceiver = TTIMetricsReceiverStub()
        let vc1 = UIViewController()
        let observer1 = TTIObserver(screen: vc1, metricsReceiver: metricsReceiver, timeProvider: timeProvider)

        let vc2 = UIViewController()
        let observer2 = TTIObserver(screen: vc2, metricsReceiver: metricsReceiver, timeProvider: timeProvider)

        timeProvider.time = time.advanced(by: .milliseconds(500))
        observer1.beforeInit()
        observer2.beforeInit()
        waitForTheNextRunLoop()

        timeProvider.time = time.advanced(by: .milliseconds(600))
        observer1.afterViewWillAppear()
        observer2.afterViewWillAppear()
        waitForTheNextRunLoop()

        timeProvider.time = time.advanced(by: .milliseconds(1300))
        observer2.afterViewDidAppear()
        waitForTheNextRunLoop()

        timeProvider.time = time.advanced(by: .milliseconds(10000))
        observer2.beforeViewWillDisappear()
        waitForTheNextRunLoop()

        timeProvider.time = time.advanced(by: .milliseconds(10100))
        observer1.afterViewWillAppear()
        waitForTheNextRunLoop()

        PerformanceMonitoring.consumerQueue.sync {}

        XCTAssertEqual(metricsReceiver.ttiMetrics?.tti, .milliseconds(800))  // between 500 and 1300
        XCTAssertEqual(metricsReceiver.ttiMetrics?.ttfr, .milliseconds(100))  // between 500 and 600
        XCTAssertEqual(metricsReceiver.lastController, vc2)

        metricsReceiver.lastController = nil
        metricsReceiver.ttiMetrics = nil

        timeProvider.time = time.advanced(by: .milliseconds(11000))
        observer1.afterViewDidAppear()

        timeProvider.time = time.advanced(by: .milliseconds(15000))
        observer1.beforeViewWillDisappear()
        PerformanceMonitoring.consumerQueue.sync {}

        // TTI shouldn't be sent
        XCTAssertNil(metricsReceiver.lastController)
        XCTAssertNil(metricsReceiver.ttiMetrics)
    }
}

class TimeProviderStub: TimeProvider {
    var time = DispatchTime(uptimeNanoseconds: 1_000_000_000)
    func now() -> DispatchTime {
        return time
    }
}

extension XCTestCase {
    func waitForTheNextRunLoop() {
        let exp = expectation(description: "runloop")
        DispatchQueue.main.asyncAfter(deadline: .now()) {
            exp.fulfill()
        }
        wait(for: [exp])
    }
}

private class MyViewController: UIViewController { }
