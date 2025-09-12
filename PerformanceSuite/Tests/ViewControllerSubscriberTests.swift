//
//  ViewControllerSubscriberTests.swift
//  PerformanceSuite
//
//  Created by Gleb Tarasov on 06/07/2021.
//

import UIKit
import XCTest

@testable import PerformanceSuite

class ViewControllerSubscriberTests: XCTestCase {

    override func setUp() {
        super.setUp()
        // Clean up any leftover swizzling from previous test failures
        try? ViewControllerSubscriber.shared.unsubscribeObservers()
    }

    override func tearDown() {
        super.tearDown()
        // Ensure swizzling is always cleaned up, even if test fails
        try? ViewControllerSubscriber.shared.unsubscribeObservers()
        // Wait for queues to complete any pending work
        PerformanceMonitoring.queue.sync { }
        PerformanceMonitoring.consumerQueue.sync { }
    }

    func testAllMethodsAreCalled() throws {
        let o = Observer()
        try ViewControllerSubscriber.shared.subscribeObserver(o)

        let vc1 = UIViewController()

        waitForMainQueueToExecute()
        XCTAssertEqual(o.viewController, vc1)
        XCTAssertEqual(o.lastMethod, .beforeInit)
        o.clear()

        let vc2 = UIViewController()

        waitForMainQueueToExecute()
        XCTAssertEqual(o.viewController, vc2)
        XCTAssertEqual(o.lastMethod, .beforeInit)
        o.clear()

        vc2.viewDidAppear(true)

        waitForMainQueueToExecute()

        XCTAssertEqual(o.viewController, vc2)
        XCTAssertEqual(o.lastMethod, .afterViewDidAppear)
        o.clear()

        vc2.viewDidAppear(true)

        waitForMainQueueToExecute()

        XCTAssertEqual(o.viewController, vc2)
        XCTAssertEqual(o.lastMethod, .afterViewDidAppear)
        o.clear()

        vc1.viewDidAppear(true)

        waitForMainQueueToExecute()

        XCTAssertEqual(o.viewController, vc1)
        XCTAssertEqual(o.lastMethod, .afterViewDidAppear)
        o.clear()

        vc2.viewWillDisappear(true)

        waitForMainQueueToExecute()
        XCTAssertEqual(o.viewController, vc2)
        XCTAssertEqual(o.lastMethod, .beforeViewWillDisappear)
        o.clear()

        vc1.viewDidLoad()

        waitForMainQueueToExecute()
        XCTAssertEqual(o.viewController, vc1)
        XCTAssertEqual(o.lastMethod, .beforeViewDidLoad)
        o.clear()

        try ViewControllerSubscriber.shared.unsubscribeObservers()
    }

    func testOrderOfInvocationIsCorrect() throws {
        let o = Observer()
        try ViewControllerSubscriber.shared.subscribeObserver(o)

        let vc = ViewController()
        waitForMainQueueToExecute()

        // beforeInit
        XCTAssertLessThan(try XCTUnwrap(o.lastTime), try XCTUnwrap(vc.lastTime))

        o.clear()
        vc.clear()

        // beforeViewDidLoad
        _ = vc.view
        waitForMainQueueToExecute()

        XCTAssertLessThan(try XCTUnwrap(o.lastTime), try XCTUnwrap(vc.lastTime))

        o.clear()
        vc.clear()

        // afterViewWillAppear
        vc.viewWillAppear(true)
        waitForMainQueueToExecute()

        XCTAssertGreaterThan(try XCTUnwrap(o.lastTime), try XCTUnwrap(vc.lastTime))

        o.clear()
        vc.clear()

        // afterViewDidAppear
        vc.viewDidAppear(true)
        waitForMainQueueToExecute()

        XCTAssertGreaterThan(try XCTUnwrap(o.lastTime), try XCTUnwrap(vc.lastTime))

        o.clear()
        vc.clear()

        // beforeViewWillDisappear
        vc.viewWillDisappear(true)
        waitForMainQueueToExecute()

        XCTAssertLessThan(try XCTUnwrap(o.lastTime), try XCTUnwrap(vc.lastTime))

        o.clear()
        vc.clear()

        // beforeViewDidDisappear
        vc.viewDidDisappear(true)
        waitForMainQueueToExecute()

        XCTAssertLessThan(try XCTUnwrap(o.lastTime), try XCTUnwrap(vc.lastTime))

        o.clear()
        vc.clear()

        try ViewControllerSubscriber.shared.unsubscribeObservers()
    }

    private func waitForMainQueueToExecute() {
        let e = expectation(description: "skip 1 run loop")

        PerformanceMonitoring.queue.async {
            DispatchQueue.main.async {
                e.fulfill()
            }
        }

        waitForExpectations(timeout: 1, handler: nil)
    }
}

private class ViewController: UIViewController {
    init() {
        super.init(nibName: nil, bundle: nil)
        lastTime = DispatchTime.now()
    }

    required init?(coder: NSCoder) {
        fatalError("not implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        lastTime = DispatchTime.now()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        lastTime = DispatchTime.now()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        lastTime = DispatchTime.now()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        lastTime = DispatchTime.now()
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        lastTime = DispatchTime.now()
    }

    var lastTime: DispatchTime?

    func clear() {
        lastTime = nil
    }
}
