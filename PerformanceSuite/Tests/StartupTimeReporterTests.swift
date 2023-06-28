//
//  StartupTimeReporterTests.swift
//  PerformanceSuite-Tests
//
//  Created by Gleb Tarasov on 06/04/2022.
//

import XCTest

@testable import PerformanceSuite

class StartupTimeReporterTests: XCTestCase {
    override func setUp() {
        super.setUp()
        StartupTimeReporter.forgetMainStartedForTests()
    }

    func testTimeCalculationsWithoutMain() {
        let receiver = StartupTimeReceiverStub()
        let reporter = StartupTimeReporter(receiver: receiver)
        XCTAssertNil(receiver.data)

        reporter.onViewDidLoadOfTheFirstViewController()
        reporter.onViewDidAppearOfTheFirstViewController()
        PerformanceMonitoring.consumerQueue.sync {}

        XCTAssertNotNil(receiver.data?.totalTime)
        XCTAssertNotNil(receiver.data?.totalBeforeViewControllerTime)
        XCTAssertNil(receiver.data?.mainTime)
        XCTAssertNil(receiver.data?.preMainTime)
    }

    func testTimeCalculationsWithMain() {
        let receiver = StartupTimeReceiverStub()
        let reporter = StartupTimeReporter(receiver: receiver)
        XCTAssertNil(receiver.data)

        StartupTimeReporter.recordMainStarted()
        reporter.onViewDidLoadOfTheFirstViewController()
        reporter.onViewDidAppearOfTheFirstViewController()
        PerformanceMonitoring.consumerQueue.sync {}

        XCTAssertNotNil(receiver.data?.totalTime)
        XCTAssertNotNil(receiver.data?.mainTime)
        XCTAssertNotNil(receiver.data?.preMainTime)
        XCTAssertNotNil(receiver.data?.totalBeforeViewControllerTime)
    }

    func testAppStartedNotification() {
        let receiver = StartupTimeReceiverStub()
        let reporter = StartupTimeReporter(receiver: receiver)
        let exp = expectation(description: "notified")
        PerformanceMonitoring.queue.async {
            XCTAssertTrue(reporter.appIsStarting)
            reporter.notifyAfterAppStarted {
                exp.fulfill()
            }
            XCTAssertTrue(reporter.appIsStarting)
            reporter.onViewDidLoadOfTheFirstViewController()
            XCTAssertTrue(reporter.appIsStarting)
            reporter.onViewDidAppearOfTheFirstViewController()
        }
        waitForExpectations(timeout: 1)
        PerformanceMonitoring.queue.sync {
            XCTAssertFalse(reporter.appIsStarting)
        }
    }

    func testStartupTimeObserver() throws {
        let receiver = StartupTimeReceiverStub()
        let reporter = StartupTimeReporter(receiver: receiver)
        let observer = StartupTimeViewControllerObserver(reporter: reporter)

        try ViewControllerSubscriber.shared.subscribeObserver(observer)

        let exp = expectation(description: "notified")

        PerformanceMonitoring.queue.sync {
            XCTAssertTrue(reporter.appIsStarting)
            reporter.notifyAfterAppStarted {
                exp.fulfill()
            }
        }

        let window = UIWindow()
        window.rootViewController = UIViewController()
        window.makeKeyAndVisible()

        waitForExpectations(timeout: 1)
        PerformanceMonitoring.queue.sync {
            XCTAssertFalse(reporter.appIsStarting)
        }

        try ViewControllerSubscriber.shared.unsubscribeObservers()
    }
}

private class StartupTimeReceiverStub: StartupTimeReceiver {
    var data: StartupTimeData?

    func startupTimeReceived(_ data: StartupTimeData) {
        self.data = data
    }
}
