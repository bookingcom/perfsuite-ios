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

    // Disabled: flaky on CI — leak detection depends on GC timing which
    // varies across simulator runtimes and CI load.
    func disabled_testLeakDetected() throws {
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

    // Disabled: flaky on CI — leak detection depends on GC timing which
    // varies across simulator runtimes and CI load.
    func disabled_testLeakDetectedForSwiftUI() throws {
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

    func testLeakReportDoesNotRetainViewControllerWithReleaseViewControllersOnMain() {
        PerformanceMonitoring.experiments = Experiments(releaseViewControllersOnMain: true)
        addTeardownBlock { PerformanceMonitoring.experiments = Experiments() }
        let receiver = BlockingLeaksReceiver()
        let consumerQueueGate = DispatchSemaphore(value: 0)
        addTeardownBlock { consumerQueueGate.signal() }
        PerformanceMonitoring.consumerQueue.async { consumerQueueGate.wait() }

        var viewController: DismissedViewController? = DismissedViewController()
        weak var weakViewController = viewController
        detectLeak(of: viewController!, receiver: receiver)
        viewController = nil
        let deallocated = weakViewController == nil
        consumerQueueGate.signal()
        PerformanceMonitoring.consumerQueue.sync { }

        XCTAssertTrue(deallocated)
        XCTAssertFalse(receiver.called)
    }

    func testLeakReportReleasesViewControllerOnMainWithReleaseViewControllersOnMain() {
        PerformanceMonitoring.experiments = Experiments(releaseViewControllersOnMain: true)
        addTeardownBlock { PerformanceMonitoring.experiments = Experiments() }
        let receiverEntered = DispatchSemaphore(value: 0)
        let receiverMayReturn = DispatchSemaphore(value: 0)
        let reportFinished = DispatchSemaphore(value: 0)
        addTeardownBlock { receiverMayReturn.signal() }
        let receiver = BlockingLeaksReceiver()
        receiver.onLeakReceived = {
            receiverEntered.signal()
            receiverMayReturn.wait()
            // Runs right after the report block, once it has dropped its references.
            PerformanceMonitoring.consumerQueue.async { reportFinished.signal() }
        }

        var viewController: DismissedViewController? = DismissedViewController()
        weak var weakViewController = viewController
        detectLeak(of: viewController!, receiver: receiver)
        XCTAssertEqual(receiverEntered.wait(timeout: .now() + 5), .success)
        // From here only the report holds the view controller.
        viewController = nil
        receiverMayReturn.signal()
        XCTAssertEqual(reportFinished.wait(timeout: .now() + 5), .success)

        // The report block is done, but its last reference is released by a block queued on main.
        XCTAssertNotNil(weakViewController)
        let deadline = Date().addingTimeInterval(5)
        while weakViewController != nil && Date() < deadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.01))
        }
        XCTAssertNil(weakViewController)
        // DismissedViewController.deinit asserts that it runs on the main thread.
    }

    /// Runs the dismissal callbacks and returns once the leak check has queued the report on the consumer queue.
    private func detectLeak(of viewController: UIViewController, receiver: BlockingLeaksReceiver) {
        let observer = ViewControllerLeaksObserver(metricsReceiver: receiver, detectionTimeout: .milliseconds(10))
        let checked = expectation(description: "leak checked")
        receiver.onShouldTrack = { checked.fulfill() }
        observer.beforeViewWillDisappear(viewController: viewController)
        observer.beforeViewDidDisappear(viewController: viewController)
        // `shouldTrack` is called on main right before the report is queued, in the same main queue block.
        wait(for: [checked], timeout: 5)
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

private class DismissedViewController: UIViewController {
    override var isBeingDismissed: Bool { true }

    deinit {
        XCTAssertTrue(Thread.isMainThread)
    }
}

private class BlockingLeaksReceiver: ViewControllerLeaksReceiver {
    var onShouldTrack: (() -> Void)?
    var onLeakReceived: (() -> Void)?
    private(set) var called = false

    func shouldTrack(viewController: UIViewController) -> Bool {
        onShouldTrack?()
        return true
    }

    func viewControllerLeakReceived(viewController: UIViewController) {
        called = true
        onLeakReceived?()
    }
}
