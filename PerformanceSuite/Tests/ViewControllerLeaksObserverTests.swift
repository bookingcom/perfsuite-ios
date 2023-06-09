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
        PerformanceSuite.experiments = Experiments(ios_adq_leak_detection_check_on_view_will_disappear: true)
    }

    override func tearDown() {
        super.tearDown()
        PerformanceSuite.experiments = Experiments()
    }

    private func performLeakTest(expectLeak: Bool, viewControllerMaker: () -> UIViewController) throws {
        let receiver = ViewControllerLeaksReceiverStub()
        receiver.expectation = expectation(description: "leak detected")
        receiver.expectation?.isInverted = !expectLeak

        let observer = ViewControllerLeaksObserver(metricsReceiver: receiver, detectionTimeout: .milliseconds(3))

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
            wait(for: [exp], timeout: 1)
        }

        PerformanceSuite.queue.sync { }
        PerformanceSuite.consumerQueue.sync { }

        wait(for: [receiver.expectation!], timeout: 1)
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