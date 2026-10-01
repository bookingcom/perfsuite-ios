//
//  TTIObserverPendingMeasurementTests.swift
//  PerformanceSuite
//
//  Created by Ahmed Nafei on 01/10/2026.
//

import UIKit
import XCTest

@testable import PerformanceSuite

/// The pending measurement `screenIsBeingCreated()` opens for a live receiver, and the TTI values around it.
class TTIObserverPendingMeasurementTests: XCTestCase {

    private typealias Handle = PendingTTIMetricsReceiverStub.Handle

    private let timeProvider = TimeProviderStub()
    private lazy var start = timeProvider.time
    private var previousQueue: DispatchQueue?

    override func setUp() {
        super.setUp()
        PerformanceMonitoring.queue.sync {}
        previousQueue = PerformanceMonitoring.changeQueueForTests(DispatchQueue.main)
        TTIObserverHelper.resetForTests()
    }

    override func tearDown() {
        TTIObserverHelper.resetForTests()
        if let previousQueue {
            PerformanceMonitoring.changeQueueForTests(previousQueue)
        }
        super.tearDown()
    }

    // MARK: - Opening and adoption

    func testCallOpensThePendingMeasurementBeforeReturning() throws {
        let receiver = PendingTTIMetricsReceiverStub()
        install(receiver)

        let before = Date()
        TTIObserverHelper.startCustomCreationTime(timeProvider: timeProvider)

        XCTAssertEqual(receiver.pendingStarts.count, 1, "a request the caller starts next must find the measurement")
        XCTAssertGreaterThanOrEqual(try XCTUnwrap(receiver.pendingStartDates.first), before)
    }

    func testCallDoesNotWaitForABusyQueue() throws {
        let queue = DispatchQueue(label: "busy_monitoring_queue")
        PerformanceMonitoring.changeQueueForTests(queue)
        let receiver = PendingTTIMetricsReceiverStub()
        install(receiver)
        queue.sync {}
        let blocker = DispatchSemaphore(value: 0)
        queue.async { blocker.wait() }

        TTIObserverHelper.startCustomCreationTime(timeProvider: timeProvider)

        XCTAssertEqual(receiver.pendingStarts.count, 1, "opened before the queue frees up")

        blocker.signal()
        queue.sync {}
        TTIObserverHelper.clearCustomCreationTime()
        queue.sync {}

        let pending = try XCTUnwrap(receiver.pendingStarts.first)
        XCTAssertEqual(receiver.pendingEnds.map(\.reason), [.creationCancelled], "the queue recorded it afterwards")
        XCTAssertTrue(receiver.pendingEnds.first?.handle === pending)
    }

    func testScreenCreatedAfterTheCallAdoptsThePendingMeasurement() throws {
        let receiver = PendingTTIMetricsReceiverStub()
        install(receiver)
        callScreenIsBeingCreated()

        runTimeline(makeObserver(receiver))

        let pending = try XCTUnwrap(receiver.pendingStarts.first)
        XCTAssertEqual(receiver.adoptedHandles.count, 1)
        XCTAssertTrue(receiver.adoptedHandles.first === pending)
        XCTAssertTrue(receiver.startedHandles.isEmpty, "the adopter starts no measurement of its own")
        XCTAssertTrue(endedHandle(receiver) === pending)
        XCTAssertEqual(pending.cancelCount, 0)
        XCTAssertTrue(receiver.pendingEnds.isEmpty)
        XCTAssertEqual(receiver.ttiMetrics?.tti, .milliseconds(330))
        XCTAssertEqual(receiver.ttiMetrics?.ttfr, .milliseconds(14))
        XCTAssertEqual(receiver.ttiMetrics?.customStart, true)
    }

    func testTTIMetricsMatchTheLegacyPathForTheSameTimeline() {
        let legacy = PendingTTIMetricsReceiverStub()
        callScreenIsBeingCreated()
        runTimeline(makeObserver(legacy))
        XCTAssertTrue(legacy.pendingStarts.isEmpty, "no hook: the 1.11.4 path")
        XCTAssertEqual(legacy.startedHandles.count, 1)

        let receiver = PendingTTIMetricsReceiverStub()
        install(receiver)
        callScreenIsBeingCreated()
        runTimeline(makeObserver(receiver))

        XCTAssertEqual(receiver.adoptedHandles.count, 1)
        XCTAssertNotNil(receiver.ttiMetrics)
        XCTAssertEqual(receiver.ttiMetrics, legacy.ttiMetrics)
    }

    func testNilPendingHandleLeavesTheLegacyPath() {
        let receiver = PendingTTIMetricsReceiverStub()
        receiver.opensPendingMeasurements = false
        install(receiver)
        callScreenIsBeingCreated()

        runTimeline(makeObserver(receiver))

        XCTAssertTrue(receiver.adoptedHandles.isEmpty)
        XCTAssertEqual(receiver.startedHandles.count, 1)
        XCTAssertEqual(receiver.ttiMetrics?.tti, .milliseconds(330))
        XCTAssertEqual(receiver.ttiMetrics?.customStart, true)
    }

    func testCallThatOpensNothingStillEndsTheEarlierPendingMeasurement() throws {
        let receiver = PendingTTIMetricsReceiverStub()
        install(receiver)
        callScreenIsBeingCreated()
        receiver.opensPendingMeasurements = false
        callScreenIsBeingCreated(at: 50)

        let pending = try XCTUnwrap(receiver.pendingStarts.first)
        XCTAssertEqual(receiver.pendingEnds.map(\.reason), [.superseded], "the anchor moved to the second call")
        XCTAssertTrue(receiver.pendingEnds.first?.handle === pending)

        runTimeline(makeObserver(receiver))

        XCTAssertTrue(receiver.adoptedHandles.isEmpty)
        XCTAssertEqual(receiver.startedHandles.count, 1)
        XCTAssertEqual(receiver.ttiMetrics?.tti, .milliseconds(280))
    }

    func testRejectedAdoptionLeavesTheScreenWithoutAMeasurement() {
        let receiver = PendingTTIMetricsReceiverStub()
        receiver.acceptsAdoption = false
        install(receiver)
        callScreenIsBeingCreated()

        runTimeline(makeObserver(receiver))

        XCTAssertEqual(receiver.adoptedHandles.count, 1)
        XCTAssertTrue(receiver.startedHandles.isEmpty, "a rejected adoption is not followed by a fresh start")
        XCTAssertEqual(receiver.endedContexts.count, 1)
        XCTAssertNil(receiver.endedContexts.first ?? nil)
        XCTAssertEqual(receiver.ttiMetrics?.tti, .milliseconds(330))
    }

    func testCachedControllerWhoseViewLoadsAfterTheCallAdoptsIt() throws {
        let receiver = PendingTTIMetricsReceiverStub()
        install(receiver)
        let observer = makeObserver(receiver)
        timeProvider.time = start
        observer.beforeInit()
        waitForTheNextRunLoop()
        waitForTheNextRunLoop()

        callScreenIsBeingCreated(at: 100)
        timeProvider.time = start.advanced(by: .milliseconds(150))
        observer.beforeViewDidLoad()
        waitForTheNextRunLoop()
        timeProvider.time = start.advanced(by: .milliseconds(200))
        observer.afterViewWillAppear()
        waitForTheNextRunLoop()
        timeProvider.time = start.advanced(by: .milliseconds(220))
        observer.afterViewDidAppear()
        waitForTheNextRunLoop()
        timeProvider.time = start.advanced(by: .milliseconds(300))
        observer.screenIsReady()
        waitForTheNextRunLoop()
        PerformanceMonitoring.consumerQueue.sync {}

        let pending = try XCTUnwrap(receiver.pendingStarts.first)
        XCTAssertTrue(receiver.adoptedHandles.first === pending)
        XCTAssertTrue(receiver.startedHandles.isEmpty)
        XCTAssertTrue(receiver.pendingEnds.isEmpty)
        XCTAssertEqual(receiver.ttiMetrics?.tti, .milliseconds(200))
        XCTAssertEqual(receiver.ttiMetrics?.ttfr, .milliseconds(50))
        XCTAssertEqual(receiver.ttiMetrics?.customStart, true)
    }

    func testScreenAlreadyMeasuringBeforeTheCallKeepsItsOwnAndEndsItNotAdopted() throws {
        // A cached controller whose view is loaded, or a screen that calls from its own `viewWillAppear`.
        let receiver = PendingTTIMetricsReceiverStub()
        install(receiver)
        let observer = makeObserver(receiver)
        timeProvider.time = start
        observer.beforeInit()
        observer.beforeViewDidLoad()

        callScreenIsBeingCreated(at: 10)
        XCTAssertEqual(receiver.pendingStarts.count, 1)

        timeProvider.time = start.advanced(by: .milliseconds(12))
        observer.afterViewWillAppear()
        waitForTheNextRunLoop()
        timeProvider.time = start.advanced(by: .milliseconds(20))
        observer.afterViewDidAppear()
        waitForTheNextRunLoop()
        timeProvider.time = start.advanced(by: .milliseconds(50))
        observer.screenIsReady()
        waitForTheNextRunLoop()
        PerformanceMonitoring.consumerQueue.sync {}

        let pending = try XCTUnwrap(receiver.pendingStarts.first)
        XCTAssertEqual(receiver.pendingEnds.map(\.reason), [.notAdopted])
        XCTAssertTrue(receiver.pendingEnds.first?.handle === pending)
        XCTAssertTrue(receiver.adoptedHandles.isEmpty)
        XCTAssertEqual(receiver.startedHandles.count, 1)
        XCTAssertEqual(receiver.ttiMetrics?.tti, .milliseconds(40), "TTI starts at the call, as in 1.11.4")
        XCTAssertEqual(receiver.ttiMetrics?.customStart, true)
    }

    func testForceLoadedScreenThatAdoptsAndNeverAppearsLeavesTheNextScreenTTIUnchanged() {
        let receiver = PendingTTIMetricsReceiverStub()
        install(receiver)
        callScreenIsBeingCreated()

        let child = makeObserver(receiver)
        withExtendedLifetime(child) {
            timeProvider.time = start.advanced(by: .milliseconds(100))
            child.beforeInit()
            child.beforeViewDidLoad()
            XCTAssertEqual(receiver.adoptedHandles.count, 1)

            runTimeline(makeObserver(receiver))

            XCTAssertEqual(receiver.startedHandles.count, 1)
            XCTAssertTrue(receiver.pendingEnds.isEmpty)
            XCTAssertEqual(receiver.ttiMetrics?.tti, .milliseconds(330))
            XCTAssertEqual(receiver.ttiMetrics?.ttfr, .milliseconds(14))
            XCTAssertEqual(receiver.ttiMetrics?.customStart, true)

            callScreenIsBeingCreated(at: 400)
            XCTAssertEqual(receiver.pendingStarts.count, 2, "the unshown child doesn't stop later calls")
        }
    }

    // MARK: - Endings

    func testCreationCancelledEndsThePendingMeasurement() throws {
        let receiver = PendingTTIMetricsReceiverStub()
        install(receiver)
        callScreenIsBeingCreated()

        TTIObserverHelper.clearCustomCreationTime()
        waitForTheNextRunLoop()

        let pending = try XCTUnwrap(receiver.pendingStarts.first)
        XCTAssertEqual(receiver.pendingEnds.map(\.reason), [.creationCancelled])
        XCTAssertTrue(receiver.pendingEnds.first?.handle === pending)

        runTimeline(makeObserver(receiver))

        XCTAssertTrue(receiver.adoptedHandles.isEmpty)
        XCTAssertEqual(receiver.startedHandles.count, 1)
        XCTAssertEqual(receiver.ttiMetrics?.tti, .milliseconds(130))
        XCTAssertEqual(receiver.ttiMetrics?.customStart, false)
    }

    func testRepeatCallSupersedesThePendingMeasurement() {
        let receiver = PendingTTIMetricsReceiverStub()
        install(receiver)
        callScreenIsBeingCreated()
        callScreenIsBeingCreated(at: 50)

        XCTAssertEqual(receiver.pendingStarts.count, 2)
        XCTAssertEqual(receiver.pendingEnds.map(\.reason), [.superseded])
        XCTAssertTrue(receiver.pendingEnds.first?.handle === receiver.pendingStarts.first)

        runTimeline(makeObserver(receiver))

        XCTAssertEqual(receiver.adoptedHandles.count, 1)
        XCTAssertTrue(receiver.adoptedHandles.first === receiver.pendingStarts.last)
        XCTAssertEqual(receiver.ttiMetrics?.tti, .milliseconds(280), "the anchor moved to the last call, as in 1.11.4")
    }

    func testScreenBackgroundedBeforeViewDidLoadEndsItNotAdoptedAndTheNextScreenKeepsItsOwnStart() {
        let receiver = PendingTTIMetricsReceiverStub()
        install(receiver)
        callScreenIsBeingCreated()

        let appStateA = AppStateListenerStub()
        let observerA = makeObserver(receiver, appState: appStateA)
        timeProvider.time = start.advanced(by: .milliseconds(150))
        observerA.beforeInit()
        appStateA.wasInBackground = true
        appStateA.didChange()
        observerA.beforeViewDidLoad()
        XCTAssertTrue(receiver.adoptedHandles.isEmpty)
        XCTAssertTrue(receiver.startedHandles.isEmpty)

        timeProvider.time = start.advanced(by: .milliseconds(200))
        observerA.afterViewWillAppear()
        waitForTheNextRunLoop()
        XCTAssertEqual(receiver.pendingEnds.map(\.reason), [.notAdopted])

        let observerB = makeObserver(receiver)
        timeProvider.time = start.advanced(by: .milliseconds(250))
        observerB.beforeInit()
        observerB.beforeViewDidLoad()
        waitForTheNextRunLoop()
        timeProvider.time = start.advanced(by: .milliseconds(300))
        observerB.afterViewWillAppear()
        waitForTheNextRunLoop()
        timeProvider.time = start.advanced(by: .milliseconds(320))
        observerB.afterViewDidAppear()
        waitForTheNextRunLoop()
        timeProvider.time = start.advanced(by: .milliseconds(400))
        observerB.screenIsReady()
        waitForTheNextRunLoop()
        PerformanceMonitoring.consumerQueue.sync {}

        XCTAssertTrue(receiver.adoptedHandles.isEmpty)
        XCTAssertEqual(receiver.startedHandles.count, 1)
        XCTAssertEqual(receiver.ttiMetrics?.tti, .milliseconds(150), "B anchors at its own init")
        XCTAssertEqual(receiver.ttiMetrics?.customStart, false)
    }

    func testPendingMeasurementNobodyAdoptsEndsAbandonedAfterMaxAge() {
        let receiver = PendingTTIMetricsReceiverStub()
        install(receiver)
        TTIObserverHelper.pendingMaxAge = .milliseconds(10)
        callScreenIsBeingCreated()

        waitOnMain(milliseconds: 100)

        XCTAssertEqual(receiver.pendingEnds.map(\.reason), [.abandoned])

        runTimeline(makeObserver(receiver))

        XCTAssertTrue(receiver.adoptedHandles.isEmpty)
        XCTAssertEqual(receiver.startedHandles.count, 1)
        XCTAssertEqual(receiver.ttiMetrics?.tti, .milliseconds(330), "the anchor stays, as in 1.11.4")
    }

    func testPendingMeasurementOlderThanMaxAgeIsNotAdopted() {
        let receiver = PendingTTIMetricsReceiverStub()
        install(receiver)
        callScreenIsBeingCreated()

        let observer = makeObserver(receiver)
        timeProvider.time = start.advanced(by: .seconds(61))
        observer.beforeInit()
        observer.beforeViewDidLoad()

        XCTAssertEqual(receiver.pendingEnds.map(\.reason), [.abandoned])
        XCTAssertTrue(receiver.adoptedHandles.isEmpty)
        XCTAssertEqual(receiver.startedHandles.count, 1)
    }

    func testExpiryAfterASupersedeOrAnAdoptionLeavesTheMeasurementsAlone() throws {
        let receiver = PendingTTIMetricsReceiverStub()
        install(receiver)
        TTIObserverHelper.pendingMaxAge = .milliseconds(10)
        callScreenIsBeingCreated()
        callScreenIsBeingCreated()

        let observer = makeObserver(receiver)
        observer.beforeInit()
        observer.beforeViewDidLoad()
        XCTAssertEqual(receiver.adoptedHandles.count, 1)

        waitOnMain(milliseconds: 100)

        XCTAssertEqual(receiver.pendingEnds.map(\.reason), [.superseded], "each measurement ends once")
        XCTAssertEqual(try XCTUnwrap(receiver.pendingStarts.last).cancelCount, 0)
    }

    func testDisableCancelsThePendingMeasurementAndAReEnabledMonitorDoesNotAdoptIt() throws {
        addTeardownBlock {
            try? PerformanceMonitoring.disable()
        }
        let first = PendingTTIMetricsReceiverStub()
        try PerformanceMonitoring.enable(config: [.screenLevelTTI(first)])
        waitForTheNextRunLoop()
        callScreenIsBeingCreated()
        let pending = try XCTUnwrap(first.pendingStarts.first)

        try PerformanceMonitoring.disable()
        waitForTheNextRunLoop()

        XCTAssertEqual(pending.cancelCount, 1)
        XCTAssertTrue(first.pendingEnds.isEmpty)

        let second = PendingTTIMetricsReceiverStub()
        try PerformanceMonitoring.enable(config: [.screenLevelTTI(second)])
        waitForTheNextRunLoop()
        let observer = makeObserver(second)
        observer.beforeInit()
        observer.beforeViewDidLoad()

        XCTAssertTrue(second.adoptedHandles.isEmpty)
        XCTAssertEqual(second.startedHandles.count, 1)
    }

    func testMeasurementOpenedJustBeforeADisableIsCancelledAndNotAdoptedAfterReEnable() throws {
        let first = PendingTTIMetricsReceiverStub()
        let second = PendingTTIMetricsReceiverStub()
        let secondHook = hook(for: second)
        // `disable()` and `enable()` on another thread, after the caller opened the measurement but before the
        // queue recorded it.
        TTIObserverHelper.installPendingHook(
            PendingScreenTTIHook(
                start: { startTime in
                    let handle = first.screenTTIPendingMeasurementStarted(at: startTime)
                    TTIObserverHelper.uninstallPendingHook()
                    TTIObserverHelper.installPendingHook(secondHook)
                    return handle
                },
                end: { first.screenTTIPendingMeasurementEnded($0, reason: $1) }
            )
        )
        waitForTheNextRunLoop()

        callScreenIsBeingCreated()

        let pending = try XCTUnwrap(first.pendingStarts.first)
        XCTAssertEqual(pending.cancelCount, 1)
        XCTAssertTrue(first.pendingEnds.isEmpty)

        runTimeline(makeObserver(second))

        XCTAssertTrue(second.adoptedHandles.isEmpty)
        XCTAssertEqual(second.startedHandles.count, 1)
        XCTAssertEqual(second.ttiMetrics?.tti, .milliseconds(330), "the anchor is set as in 1.11.4")
    }

    // MARK: - customStart

    func testCustomStartIsSetOnTheReadinessFallbackPath() {
        let receiver = PendingTTIMetricsReceiverStub()
        install(receiver)
        callScreenIsBeingCreated()

        let observer = makeObserver(receiver)
        timeProvider.time = start.advanced(by: .milliseconds(200))
        observer.beforeInit()
        observer.beforeViewDidLoad()
        waitForTheNextRunLoop()
        timeProvider.time = start.advanced(by: .milliseconds(214))
        observer.afterViewWillAppear()
        waitForTheNextRunLoop()
        timeProvider.time = start.advanced(by: .milliseconds(230))
        observer.afterViewDidAppear()
        waitForTheNextRunLoop()
        timeProvider.time = start.advanced(by: .milliseconds(330))
        observer.beforeViewWillDisappear()
        waitForTheNextRunLoop()
        PerformanceMonitoring.consumerQueue.sync {}

        XCTAssertEqual(receiver.adoptedHandles.count, 1)
        XCTAssertEqual(receiver.ttiMetrics?.readyFallback, true)
        XCTAssertEqual(receiver.ttiMetrics?.customStart, true)
        XCTAssertEqual(receiver.ttiMetrics?.tti, .milliseconds(230))
    }

    // MARK: - Helpers

    private func install(_ receiver: PendingTTIMetricsReceiverStub) {
        TTIObserverHelper.installPendingHook(hook(for: receiver))
        waitForTheNextRunLoop()
    }

    private func hook(for receiver: PendingTTIMetricsReceiverStub) -> PendingScreenTTIHook {
        PendingScreenTTIHook(
            start: { receiver.screenTTIPendingMeasurementStarted(at: $0) },
            end: { receiver.screenTTIPendingMeasurementEnded($0, reason: $1) }
        )
    }

    private func callScreenIsBeingCreated(at milliseconds: Int = 0) {
        timeProvider.time = start.advanced(by: .milliseconds(milliseconds))
        TTIObserverHelper.startCustomCreationTime(timeProvider: timeProvider)
        waitForTheNextRunLoop()
    }

    private func makeObserver<T: TTIMetricsReceiver>(
        _ receiver: T,
        appState: AppStateListenerStub = AppStateListenerStub()
    ) -> TTIObserver<T> where T.ScreenIdentifier == UIViewController {
        TTIObserver(screen: UIViewController(), metricsReceiver: receiver, timeProvider: timeProvider, appStateListener: appState)
    }

    /// `init` and `viewDidLoad` at +200 ms in one run loop, `viewWillAppear` +214, `viewDidAppear` +230, ready +330.
    private func runTimeline<T: TTIMetricsReceiver>(_ observer: TTIObserver<T>) {
        timeProvider.time = start.advanced(by: .milliseconds(200))
        observer.beforeInit()
        observer.beforeViewDidLoad()
        waitForTheNextRunLoop()
        timeProvider.time = start.advanced(by: .milliseconds(214))
        observer.afterViewWillAppear()
        waitForTheNextRunLoop()
        timeProvider.time = start.advanced(by: .milliseconds(230))
        observer.afterViewDidAppear()
        waitForTheNextRunLoop()
        timeProvider.time = start.advanced(by: .milliseconds(330))
        observer.screenIsReady()
        waitForTheNextRunLoop()
        PerformanceMonitoring.consumerQueue.sync {}
    }

    private func endedHandle(_ receiver: PendingTTIMetricsReceiverStub) -> Handle? {
        (receiver.endedContexts.first ?? nil) as? Handle
    }

    private func waitOnMain(milliseconds: Int) {
        let exp = expectation(description: "delay")
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(milliseconds)) {
            exp.fulfill()
        }
        wait(for: [exp], timeout: 5)
    }
}
