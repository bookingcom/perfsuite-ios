//
//  ViewControllerLeaksObserverTests.swift
//  PerformanceSuite-Tests
//
//  Created by Gleb Tarasov on 23/06/2022.
//

import SwiftUI
import XCTest

@testable import PerformanceSuite

// swiftlint:disable force_unwrapping
class ViewControllerLeaksObserverTests: XCTestCase {

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    override func tearDown() {
        super.tearDown()
        // Ensure swizzling is always cleaned up, even if test fails
        try? ViewControllerSubscriber.shared.unsubscribeObservers()
        // Wait for queues to complete any pending work
        PerformanceMonitoring.queue.sync { }
        PerformanceMonitoring.consumerQueue.sync { }
    }

    private func performLeakTest(expectLeak: Bool, viewControllerMaker: () -> UIViewController) throws {
        // Clean up any leftover swizzling from previous test failures
        try? ViewControllerSubscriber.shared.unsubscribeObservers()

        let receiver = ViewControllerLeaksReceiverStub()
        receiver.expectation = expectation(description: "leak detected")
        receiver.expectation?.isInverted = !expectLeak

        let observer = ViewControllerLeaksObserver(metricsReceiver: receiver, detectionTimeout: .milliseconds(50))

        try ViewControllerSubscriber.shared.subscribeObserver(observer)

        let rootViewController = UIViewController()
        let window = makeWindow()
        window.rootViewController = rootViewController
        window.makeKeyAndVisible()

        weak var weakViewController: UIViewController?
        autoreleasepool {
            let exp = expectation(description: "view controller presentation")
            var strongViewController: UIViewController? = viewControllerMaker()
            weakViewController = strongViewController
            if let viewController = strongViewController {
                rootViewController.present(viewController, animated: false) {
                    viewController.dismiss(animated: false) {
                        strongViewController = nil
                        exp.fulfill()
                    }
                }
            }
            wait(for: [exp], timeout: 5)
        }

        PerformanceMonitoring.queue.sync { }
        PerformanceMonitoring.consumerQueue.sync { }

        wait(for: [receiver.expectation!], timeout: 5)
        if expectLeak {
            let vc = weakViewController
            XCTAssertNotNil(vc)
            XCTAssertEqual(receiver.leakDetected, vc)
        } else {
            XCTAssertNil(receiver.leakDetected)
        }

        try ViewControllerSubscriber.shared.unsubscribeObservers()
    }

    func testLeakDetected() throws {
        var viewController: UIViewController?
        try performLeakTest(expectLeak: true) {
            let result = UIViewController()
            viewController = result
            return result
        }
        // to avoid deallocation use viewController here
        _ = viewController
    }

    func testNoLeakNotDetected() throws {
        try performLeakTest(expectLeak: false) {
            return UIViewController()
        }
    }

    func testNoLeakDetectedForException() throws {
        var viewController: UIViewController?
        try performLeakTest(expectLeak: false) {
            let result = UIViewControllerLeakIgnored()
            viewController = result
            return result
        }
        // to avoid deallocation use viewController here
        _ = viewController
    }

    func testLeakDetectedForSwiftUI() throws {
        var viewController: UIViewController?
        try performLeakTest(expectLeak: true) {
            let result = UIHostingController(rootView: Text("test"))
            viewController = result
            return result
        }
        // to avoid deallocation use viewController here
        _ = viewController
    }

    func testNoLeakDetectedForSwiftUIException() throws {
        var viewController: UIViewController?
        try performLeakTest(expectLeak: false) {
            let result = UIHostingController(rootView: ViewLeakIgnored())
            viewController = result
            return result
        }
        // to avoid deallocation use viewController here
        _ = viewController
    }
}

private class UIViewControllerLeakIgnored: UIViewController, LeakCheckDisabled {}

private struct ViewLeakIgnored: View, LeakCheckDisabled {
    var body: some View {
        return Text("test")
    }
}

private class ViewControllerLeaksReceiverStub: ViewControllerLeaksReceiver {
    func viewControllerLeakReceived(viewController: UIViewController) {
        leakDetected = viewController
        expectation?.fulfill()
    }
    var leakDetected: UIViewController?
    var expectation: XCTestExpectation?
}
