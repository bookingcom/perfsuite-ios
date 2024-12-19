//
//  TTIObserverExtensionTests.swift
//  PerformanceSuite
//
//  Created by Gleb Tarasov on 08/12/2021.
//

import SwiftUI
import UIKit
import XCTest

@testable import PerformanceSuite

// swiftlint:disable function_body_length
class TTIObserverExtensionTests: XCTestCase {

    private let timeProvider = TimeProviderStub()
    private var metricsReceiver = TTIMetricsReceiverStub()

    override func setUpWithError() throws {
        try super.setUpWithError()
        defaultTimeProvider = timeProvider
        metricsReceiver = TTIMetricsReceiverStub()
        try PerformanceMonitoring.enable(config: [.screenLevelTTI(metricsReceiver)])
    }

    override func tearDownWithError() throws {
        try super.tearDownWithError()
        defaultTimeProvider = DefaultTimeProvider()

        PerformanceMonitoring.queue.sync {}
        PerformanceMonitoring.consumerQueue.sync {}

        try PerformanceMonitoring.disable()
    }

    func testAllViewControllerMethodsAreCalledWhenMonitoringIsEnabled() {
        let navigation = UINavigationController(rootViewController: UIViewController())
        let window = makeWindow()
        window.rootViewController = navigation
        window.makeKeyAndVisible()

        let exp = expectation(description: "vc appeared")
        let vc = OutputViewController()
        vc.viewAppeared = {
            exp.fulfill()
        }

        navigation.pushViewController(vc, animated: false)
        waitForExpectations(timeout: 300, handler: nil)

        let exp2 = expectation(description: "vc disappeared")
        vc.viewDisappeared = {
            exp2.fulfill()
        }

        navigation.pushViewController(UIViewController(), animated: false)
        waitForExpectations(timeout: 3, handler: nil)

        let desiredOutput = """
            viewDidLoad
            viewWillAppear
            viewWillLayoutSubviews
            viewDidLayoutSubviews
            viewDidAppear
            viewWillDisappear
            viewDidDisappear

            """
        XCTAssertEqual(vc.output, desiredOutput)
    }

    func testTTIIsFinishedWhenViewDisappearedByDefault() {
        let root = OutputViewController()
        root.title = "root"
        let vc1 = OutputViewController()
        vc1.title = "vc1"
        let vc2 = OutputViewController()
        vc2.title = "vc2"
        let navigation = UINavigationController(rootViewController: root)

        let exp1 = expectation(description: "root appeared")
        root.viewAppeared = {
            DispatchQueue.main.async {
                exp1.fulfill()
            }
        }

        let window = makeWindow()
        window.rootViewController = navigation
        window.makeKeyAndVisible()

        waitForExpectations(timeout: 1, handler: nil)

        let exp2 = expectation(description: "vc1 appeared")
        vc1.viewAppeared = {
            DispatchQueue.main.async {
                exp2.fulfill()
            }
        }

        navigation.pushViewController(vc1, animated: false)

        waitForExpectations(timeout: 1, handler: nil)

        PerformanceMonitoring.queue.sync {}
        PerformanceMonitoring.consumerQueue.sync {}

        XCTAssertEqual(metricsReceiver.lastController?.title, "root")
        XCTAssertNotNil(metricsReceiver.ttiMetrics)

        let exp3 = expectation(description: "vc2 appeared")
        vc2.viewAppeared = {
            DispatchQueue.main.async {
                exp3.fulfill()
            }
        }

        DispatchQueue.main.async {
            navigation.pushViewController(vc2, animated: false)
        }

        waitForExpectations(timeout: 100, handler: nil)

        PerformanceMonitoring.queue.sync {}
        PerformanceMonitoring.consumerQueue.sync {}

        XCTAssertEqual(metricsReceiver.lastController?.title, "vc1")
        XCTAssertNotNil(metricsReceiver.ttiMetrics)
    }

    func testNoTTIForViewControllerWithoutScreenIsReady() {
        let vc = OutputViewController()
        vc.title = "vc"

        let exp = expectation(description: "viewDidAppear")
        vc.viewAppeared = {
            DispatchQueue.main.async {
                exp.fulfill()
            }
        }

        let window = makeWindow()
        window.rootViewController = vc
        window.makeKeyAndVisible()

        PerformanceMonitoring.queue.sync {}
        PerformanceMonitoring.consumerQueue.sync {}

        XCTAssertNil(metricsReceiver.ttiMetrics)
        XCTAssertNil(metricsReceiver.lastController)

        waitForExpectations(timeout: 3, handler: nil)

        PerformanceMonitoring.queue.sync {}
        PerformanceMonitoring.consumerQueue.sync {}

        XCTAssertNil(metricsReceiver.ttiMetrics)
        XCTAssertNil(metricsReceiver.lastController)
    }

    func testScreenIsReadyForViewControllerGeneratesTTIMetrics() {
        let vc = OutputViewController()
        vc.title = "vc"

        let exp = expectation(description: "viewDidAppear")
        vc.viewAppeared = {
            DispatchQueue.main.async {
                exp.fulfill()
            }
        }

        let window = makeWindow()
        window.rootViewController = vc
        window.makeKeyAndVisible()

        PerformanceMonitoring.queue.sync {}
        PerformanceMonitoring.consumerQueue.sync {}

        XCTAssertNil(metricsReceiver.ttiMetrics)
        XCTAssertNil(metricsReceiver.lastController)

        DispatchQueue.main.async {
            vc.screenIsReady()
        }

        waitForExpectations(timeout: 3, handler: nil)

        PerformanceMonitoring.queue.sync {}
        PerformanceMonitoring.consumerQueue.sync {}

        PerformanceMonitoring.queue.sync {}
        PerformanceMonitoring.consumerQueue.sync {}

        XCTAssertNotNil(metricsReceiver.ttiMetrics)
        XCTAssertEqual(metricsReceiver.lastController?.title, "vc")
    }

    func testScreenIsReadyForSwiftUIViewGeneratesTTIMetrics() {
        let vc = HostingControllerWithAppeared(rootView: ViewIsReadyOnAppear())
        vc.title = "hosting vc"

        let window = makeWindow()
        window.rootViewController = vc
        window.makeKeyAndVisible()

        let exp = expectation(description: "viewDidAppear")
        vc.viewAppeared = {
            exp.fulfill()
        }

        waitForExpectations(timeout: 3, handler: nil)

        PerformanceMonitoring.queue.sync {}
        PerformanceMonitoring.consumerQueue.sync {}

        XCTAssertNotNil(metricsReceiver.ttiMetrics)
        XCTAssertEqual(metricsReceiver.lastController?.title, "hosting vc")
    }

    func testCustomInitTimeForViewControllersInsideTabBarController() {
        let now = makeRandomTime()
        timeProvider.time = now

        let vc1 = OutputViewController()
        vc1.title = "vc1"

        let vc2 = OutputViewController()
        vc2.title = "vc2"

        let vc3 = OutputViewController()
        vc3.title = "vc3"

        PerformanceMonitoring.queue.sync {}
        PerformanceMonitoring.consumerQueue.sync {}

        timeProvider.time = now.advanced(by: .seconds(1))

        let exp1 = expectation(description: "viewDidAppear vc1")
        vc1.viewAppeared = {
            DispatchQueue.main.async {
                exp1.fulfill()
            }
        }

        let tabbar = UITabBarController()
        tabbar.viewControllers = [vc1, vc2, vc3]

        let window = makeWindow()
        window.rootViewController = tabbar
        window.makeKeyAndVisible()

        wait(for: [exp1], timeout: 3)

        PerformanceMonitoring.queue.sync {}
        PerformanceMonitoring.consumerQueue.sync {}

        // for the first controller we should calculate TTI between `init` and `screenIsReady` -> 1 second
        vc1.screenIsReady()

        PerformanceMonitoring.queue.sync {}
        PerformanceMonitoring.consumerQueue.sync {}

        XCTAssertEqual(metricsReceiver.lastController?.title, "vc1")
        XCTAssertEqual(metricsReceiver.ttiMetrics?.tti, .seconds(1))

        timeProvider.time = now.advanced(by: .seconds(5))

        let exp2 = expectation(description: "viewDidDisappear vc1")
        vc1.viewDisappeared = {
            DispatchQueue.main.async {
                exp2.fulfill()
            }
        }

        DispatchQueue.main.async {
            self.timeProvider.time = now.advanced(by: .seconds(5))
            tabbar.selectedIndex = 1
        }

        waitForExpectations(timeout: 3, handler: nil)

        PerformanceMonitoring.queue.sync {}
        PerformanceMonitoring.consumerQueue.sync {}

        self.timeProvider.time = now.advanced(by: .seconds(12))
        // for the second controller we should calculate TTI between `setSelectedIndex` and `screenIsReady` -> 7 seconds
        vc2.screenIsReady()

        PerformanceMonitoring.queue.sync {}
        PerformanceMonitoring.consumerQueue.sync {}

        XCTAssertEqual(metricsReceiver.lastController?.title, "vc2")
        XCTAssertEqual(metricsReceiver.ttiMetrics?.tti, .seconds(7))

        let exp3 = expectation(description: "viewDidDisappear vc2")
        vc2.viewDisappeared = {
            DispatchQueue.main.async {
                exp3.fulfill()
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(10)) {
            self.timeProvider.time = now.advanced(by: .seconds(16))
            tabbar.selectedViewController = vc3
        }

        waitForExpectations(timeout: 3, handler: nil)

        PerformanceMonitoring.queue.sync {}
        PerformanceMonitoring.consumerQueue.sync {}

        self.timeProvider.time = now.advanced(by: .seconds(18))
        // for the third controller we should calculate TTI between `setSelectedViewController` and `screenIsReady` -> 2 seconds
        vc3.screenIsReady()

        PerformanceMonitoring.queue.sync {}
        PerformanceMonitoring.consumerQueue.sync {}

        XCTAssertEqual(metricsReceiver.lastController?.title, "vc3")
        XCTAssertEqual(metricsReceiver.ttiMetrics?.tti, .seconds(2))

    }

    func testScreenIsReadyForChildViewController() throws {
        metricsReceiver.shouldTrack = { vc in
            return (vc as? OutputViewController)?.outputTitle == "vc1"
        }

        let now = makeRandomTime()
        timeProvider.time = now

        let vc1 = OutputViewController(outputTitle: "vc1")
        let vc2 = OutputViewController(outputTitle: "vc2")

        let exp1 = expectation(description: "viewDidAppear vc1")
        let exp2 = expectation(description: "viewDidAppear vc2")
        vc1.viewAppeared = {
            exp1.fulfill()
        }

        vc2.viewAppeared = {
            exp2.fulfill()
        }

        vc2.willMove(toParent: vc1)
        vc1.addChild(vc2)
        vc1.view.addSubview(vc2.view)
        vc2.didMove(toParent: vc1)

        PerformanceMonitoring.queue.sync {}
        PerformanceMonitoring.consumerQueue.sync {}

        timeProvider.time = now.advanced(by: .seconds(1))

        let window = makeWindow()
        window.rootViewController = vc1
        window.makeKeyAndVisible()

        wait(for: [exp1, exp2], timeout: 3)

        PerformanceMonitoring.queue.sync {}
        PerformanceMonitoring.consumerQueue.sync {}

        // we call screenIsReady for the child, but it should work for the parent
        vc2.screenIsReady()
        waitForTheNextRunLoop()

        PerformanceMonitoring.queue.sync {}
        PerformanceMonitoring.consumerQueue.sync {}

        XCTAssertNotNil(metricsReceiver.ttiMetrics)
        XCTAssertEqual(metricsReceiver.ttiMetrics?.tti, .seconds(1))

        let ovc = try XCTUnwrap(metricsReceiver.lastController as? OutputViewController)
        XCTAssertEqual(ovc.outputTitle, "vc1")
    }

    private func makeRandomTime() -> DispatchTime {
        DispatchTime(uptimeNanoseconds: 10_000_000 + UInt64.random(in: 0..<100000))
    }
}
