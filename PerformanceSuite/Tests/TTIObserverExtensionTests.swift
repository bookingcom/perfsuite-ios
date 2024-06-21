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
        try PerformanceMonitoring.enable(config: [.screenLevelTTI(metricsReceiver)], experiments: Experiments(observersOnBackgroundQueue: true))
    }

    override func tearDownWithError() throws {
        try super.tearDownWithError()
        defaultTimeProvider = DefaultTimeProvider()
        try PerformanceMonitoring.disable()
        PerformanceMonitoring.experiments = Experiments()
    }

    func testAllViewControllerMethodsAreCalledWhenMonitoringIsEnabled() {
        let navigation = UINavigationController(rootViewController: UIViewController())
        let window = makeWindow()
        window.rootViewController = navigation
        window.makeKeyAndVisible()

        let exp = expectation(description: "vc appeared")
        let vc = MyViewController()
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
        let root = MyViewController()
        root.title = "root"
        let vc1 = MyViewController()
        vc1.title = "vc1"
        let vc2 = MyViewController()
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
        let vc = MyViewController()
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
        let vc = MyViewController()
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
        let vc = MyHostingController(rootView: MyView())
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
        let now = DispatchTime(uptimeNanoseconds: 10_000_000)
        timeProvider.time = now

        let vc1 = MyViewController()
        vc1.title = "vc1"

        let vc2 = MyViewController()
        vc2.title = "vc2"

        let vc3 = MyViewController()
        vc3.title = "vc3"

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

        waitForExpectations(timeout: 3, handler: nil)

        // for the first controller we should calculate TTI between `init` and `screenIsReady` -> 1 second
        vc1.screenIsReady()

        PerformanceMonitoring.queue.sync {}
        PerformanceMonitoring.consumerQueue.sync {}

        XCTAssertNotNil(metricsReceiver.ttiMetrics)
        XCTAssertEqual(metricsReceiver.ttiMetrics?.tti, .seconds(1))
        XCTAssertEqual(metricsReceiver.lastController?.title, "vc1")

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

        self.timeProvider.time = now.advanced(by: .seconds(12))
        // for the second controller we should calculate TTI between `setSelectedIndex` and `screenIsReady` -> 7 seconds
        vc2.screenIsReady()

        PerformanceMonitoring.queue.sync {}
        PerformanceMonitoring.consumerQueue.sync {}

        XCTAssertNotNil(metricsReceiver.ttiMetrics)
        XCTAssertEqual(metricsReceiver.ttiMetrics?.tti, .seconds(7))
        XCTAssertEqual(metricsReceiver.lastController?.title, "vc2")

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

        self.timeProvider.time = now.advanced(by: .seconds(18))
        // for the third controller we should calculate TTI between `setSelectedViewController` and `screenIsReady` -> 2 seconds
        vc3.screenIsReady()

        PerformanceMonitoring.queue.sync {}
        PerformanceMonitoring.consumerQueue.sync {}

        XCTAssertNotNil(metricsReceiver.ttiMetrics)
        XCTAssertEqual(metricsReceiver.ttiMetrics?.tti, .seconds(2))
        XCTAssertEqual(metricsReceiver.lastController?.title, "vc3")
    }

    func testScreenIsReadyForChildViewController() {
        let now = DispatchTime(uptimeNanoseconds: 10_000_000)
        timeProvider.time = now

        let vc1 = MyViewController()
        vc1.title = "vc1"

        let vc2 = UIViewController()
        vc2.title = "vc2"

        vc1.addChild(vc2)

        timeProvider.time = now.advanced(by: .seconds(1))

        let exp1 = expectation(description: "viewDidAppear vc1")
        vc1.viewAppeared = {
            DispatchQueue.main.async {
                exp1.fulfill()
            }
        }

        let window = makeWindow()
        window.rootViewController = vc1
        window.makeKeyAndVisible()

        waitForExpectations(timeout: 3, handler: nil)

        // we call screenIsReady for the child, but it should work for the parent
        vc2.screenIsReady()

        PerformanceMonitoring.queue.sync {}
        PerformanceMonitoring.consumerQueue.sync {}

        XCTAssertNotNil(metricsReceiver.ttiMetrics)
        XCTAssertEqual(metricsReceiver.ttiMetrics?.tti, .seconds(1))
        XCTAssertEqual(metricsReceiver.lastController?.title, "vc1")
    }
}

private class MyHostingController<T: View>: UIHostingController<T> {

    var viewAppeared: () -> Void = {}

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        DispatchQueue.main.async {
            self.viewAppeared()
        }
    }
}

private class MyViewController: UIViewController {

    var viewDisappeared: () -> Void = {}
    var viewAppeared: () -> Void = {}
    var output = ""

    override func viewDidLoad() {
        super.viewDidLoad()
        output += "viewDidLoad\n"
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        output += "viewWillAppear\n"
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        output += "viewDidAppear\n"
        viewAppeared()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        output += "viewWillDisappear\n"
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        output += "viewDidDisappear\n"

        viewDisappeared()
    }

    override func viewWillLayoutSubviews() {
        super.viewWillLayoutSubviews()
        output += "viewWillLayoutSubviews\n"
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        output += "viewDidLayoutSubviews\n"
    }
}

private struct MyView: View {
    var body: some View {
        return Text("test").screenIsReadyOnAppear()
    }
}
