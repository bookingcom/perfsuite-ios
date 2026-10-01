//
//  TTIObserverReadyFallbackTests.swift
//  PerformanceSuite
//
//  Created by Ahmed Nafei on 30/09/2026.
//

import UIKit
import XCTest

@testable import PerformanceSuite

/// `TTIMetrics.readyFallback` when `viewWillDisappear` arrives before `viewDidAppear`. The plain fallback and the
/// readiness paths are pinned in `TTIObserverTests`.
class TTIObserverReadyFallbackTests: XCTestCase {

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

    func testDisappearBeforeAppearIsNotAFallbackWhenReadinessArrivesLater() {
        // The disappear fallback has no `viewDidAppear` to fall back to, so nothing reports; the later
        // readiness call and appear report a real readiness TTI.
        let timeProvider = TimeProviderStub()
        let time = timeProvider.time

        let metricsReceiver = TTIMetricsReceiverStub()
        let observer = TTIObserver(screen: UIViewController(), metricsReceiver: metricsReceiver, timeProvider: timeProvider)

        observer.beforeInit()
        waitForTheNextRunLoop()

        timeProvider.time = time.advanced(by: .milliseconds(8))
        observer.afterViewWillAppear()
        waitForTheNextRunLoop()

        timeProvider.time = time.advanced(by: .milliseconds(9))
        observer.beforeViewWillDisappear()
        waitForTheNextRunLoop()
        PerformanceMonitoring.consumerQueue.sync {}
        XCTAssertNil(metricsReceiver.ttiMetrics)

        timeProvider.time = time.advanced(by: .milliseconds(20))
        observer.screenIsReady()
        waitForTheNextRunLoop()
        PerformanceMonitoring.consumerQueue.sync {}
        XCTAssertNil(metricsReceiver.ttiMetrics)

        timeProvider.time = time.advanced(by: .milliseconds(30))
        observer.afterViewDidAppear()
        waitForTheNextRunLoop()
        PerformanceMonitoring.consumerQueue.sync {}

        XCTAssertNotNil(metricsReceiver.ttiMetrics)
        XCTAssertEqual(metricsReceiver.ttiMetrics?.tti, .milliseconds(30))
        XCTAssertEqual(metricsReceiver.ttiMetrics?.readyFallback, false)
        XCTAssertEqual(metricsReceiver.ttiMetrics?.reportDelay, .zero)
    }

    func testDisappearBeforeAppearThenRealFallbackIsAFallback() {
        let timeProvider = TimeProviderStub()
        let time = timeProvider.time

        let metricsReceiver = TTIMetricsReceiverStub()
        let observer = TTIObserver(screen: UIViewController(), metricsReceiver: metricsReceiver, timeProvider: timeProvider)

        observer.beforeInit()
        waitForTheNextRunLoop()

        timeProvider.time = time.advanced(by: .milliseconds(8))
        observer.afterViewWillAppear()
        waitForTheNextRunLoop()

        timeProvider.time = time.advanced(by: .milliseconds(9))
        observer.beforeViewWillDisappear()
        waitForTheNextRunLoop()

        timeProvider.time = time.advanced(by: .milliseconds(30))
        observer.afterViewDidAppear()
        waitForTheNextRunLoop()
        PerformanceMonitoring.consumerQueue.sync {}
        XCTAssertNil(metricsReceiver.ttiMetrics)

        timeProvider.time = time.advanced(by: .milliseconds(500))
        observer.beforeViewWillDisappear()
        waitForTheNextRunLoop()
        PerformanceMonitoring.consumerQueue.sync {}

        XCTAssertNotNil(metricsReceiver.ttiMetrics)
        XCTAssertEqual(metricsReceiver.ttiMetrics?.tti, .milliseconds(30))
        XCTAssertEqual(metricsReceiver.ttiMetrics?.readyFallback, true)
        XCTAssertEqual(metricsReceiver.ttiMetrics?.reportDelay, .milliseconds(470))
    }
}
