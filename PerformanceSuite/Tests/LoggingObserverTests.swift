//
//  LoggingObserverTests.swift
//  PerformanceSuite-Tests
//
//  Created by Gleb Tarasov on 23/09/2022.
//

import SwiftUI
import XCTest

@testable import PerformanceSuite

final class LoggingObserverTests: XCTestCase {

    func testMethodsAreCalled() {
        let stub = LoggingReceiverStub()
        let observer = LoggingObserver(screen: "view controller", receiver: stub)

        XCTAssertNil(stub.method)
        XCTAssertNil(stub.viewController)

        observer.beforeInit()
        PerformanceMonitoring.consumerQueue.sync {}
        XCTAssertEqual(stub.method, "onInit")
        XCTAssertEqual(stub.key, "view controller")
        stub.clear()

        observer.beforeViewDidLoad()
        PerformanceMonitoring.consumerQueue.sync {}
        XCTAssertEqual(stub.method, "onViewDidLoad")
        XCTAssertEqual(stub.key, "view controller")
        stub.clear()

        observer.afterViewWillAppear()
        PerformanceMonitoring.consumerQueue.sync {}
        XCTAssertEqual(stub.method, "onViewWillAppear")
        XCTAssertEqual(stub.key, "view controller")
        stub.clear()

        observer.afterViewDidAppear()
        PerformanceMonitoring.consumerQueue.sync {}
        XCTAssertEqual(stub.method, "onViewDidAppear")
        XCTAssertEqual(stub.key, "view controller")
        stub.clear()

        observer.beforeViewWillDisappear()
        PerformanceMonitoring.consumerQueue.sync {}
        XCTAssertEqual(stub.method, "onViewWillDisappear")
        XCTAssertEqual(stub.key, "view controller")
        stub.clear()
    }

    func testReceiverNeverReleasesViewControllerLastWithReleaseViewControllersOnMain() {
        enableReleaseViewControllersOnMain()
        for callback in LoggingCallback.allCases {
            // The receiver's release is not the last one: the observer still holds the view controller after the
            // consumer block has finished, and releases it on main.
            XCTAssertTrue(viewControllerSurvivesConsumerBlock(callback), "\(callback)")
        }
    }

    func testReceiverReleasesViewControllerLastWithoutReleaseViewControllersOnMain() {
        for callback in LoggingCallback.allCases {
            // Base: the observer takes no extra retain, so the receiver releases the view controller last, on the queue.
            XCTAssertFalse(viewControllerSurvivesConsumerBlock(callback), "\(callback)")
        }
    }

    func testViewControllerIsNotHeldWhileQueuedWithReleaseViewControllersOnMain() {
        enableReleaseViewControllersOnMain()
        let receiver = ViewControllerLoadingReceiver()
        let factory = makeLoggingFactory(receiver: receiver)
        let gate = DispatchSemaphore(value: 0)
        var gateOpened = false
        let openGate = {
            if !gateOpened {
                gateOpened = true
                gate.signal()
            }
        }
        addTeardownBlock(openGate)
        PerformanceMonitoring.consumerQueue.async {
            gate.wait()
        }

        var viewController: UIViewController? = UIViewController()
        weak var weakViewController = viewController
        for callback in LoggingCallback.allCases {
            callback.call(factory, viewController!)
        }
        viewController = nil
        PerformanceMonitoring.queue.sync { }
        // Every receiver call is still queued, yet nothing keeps the view controller alive.
        waitUntilDeallocated { weakViewController == nil }

        openGate()
        PerformanceMonitoring.consumerQueue.sync { }
        XCTAssertEqual(receiver.methods, LoggingCallback.allCases.map(\.receiverMethod))
        XCTAssertEqual(receiver.loadedViewControllers, 0)
    }

    func testViewControllerAutoreleasedByReceiverIsNotReleasedLastWithReleaseViewControllersOnMain() {
        enableReleaseViewControllersOnMain()
        let receiver = ViewControllerLoadingReceiver()
        receiver.autoreleasesViewController = true
        let factory = makeLoggingFactory(receiver: receiver)
        let gate = DispatchSemaphore(value: 0)
        let nextItemStarted = DispatchSemaphore(value: 0)
        let nextItemBlocked = DispatchSemaphore(value: 0)
        addTeardownBlock {
            gate.signal()
            nextItemBlocked.signal()
        }

        // Queue the receiver call and a blocking item behind a gate, so one consumer thread runs both without returning
        // in between: that thread cannot drain a pool of its own until the blocking item ends.
        PerformanceMonitoring.consumerQueue.async {
            gate.wait()
        }
        weak var weakViewController: UIViewController?
        autoreleasepool {
            let viewController = UIViewController()
            weakViewController = viewController
            factory.afterViewDidAppear(viewController: viewController)
        }
        PerformanceMonitoring.queue.sync { }
        PerformanceMonitoring.consumerQueue.async {
            nextItemStarted.signal()
            nextItemBlocked.wait()
        }
        gate.signal()
        nextItemStarted.wait()
        // The receiver's autoreleased reference is gone already: main releases the last one.
        waitUntilDeallocated { weakViewController == nil }

        nextItemBlocked.signal()
        PerformanceMonitoring.consumerQueue.sync { }
        XCTAssertEqual(receiver.methods, ["onViewDidAppear"])
        XCTAssertEqual(receiver.loadedViewControllers, 1)
    }

    private func enableReleaseViewControllersOnMain() {
        PerformanceMonitoring.experiments = Experiments(releaseViewControllersOnMain: true)
        addTeardownBlock {
            PerformanceMonitoring.experiments = Experiments()
        }
    }

    private func makeLoggingFactory(receiver: ViewControllerLoadingReceiver) -> ViewControllerObserver {
        return ViewControllerObserverFactory<LoggingObserver, ViewControllerLoadingReceiver>(metricsReceiver: receiver) { screen in
            LoggingObserver(screen: screen, receiver: receiver)
        }
    }

    /// Runs `callback` through the logging observer factory. The receiver loads the view controller from its screen
    /// identifier, and while it holds it the test drops every other reference. Returns whether the view controller is
    /// still alive once the consumer block has finished; it is then checked to die after main turns.
    private func viewControllerSurvivesConsumerBlock(_ callback: LoggingCallback, file: StaticString = #filePath, line: UInt = #line) -> Bool {
        let receiver = ViewControllerLoadingReceiver()
        let factory = makeLoggingFactory(receiver: receiver)
        let loaded = DispatchSemaphore(value: 0)
        let dropped = DispatchSemaphore(value: 0)
        receiver.whileHoldingViewController = {
            loaded.signal()
            dropped.wait()
        }

        weak var weakViewController: UIViewController?
        // The pool drains main-thread temporaries before the receiver lets go.
        autoreleasepool {
            let viewController = UIViewController()
            weakViewController = viewController
            callback.call(factory, viewController)
            loaded.wait()
        }
        // Let the factory's own main-queue release run: only the receiver (and the observer, if any) hold it now.
        PerformanceMonitoring.queue.sync { }
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        let heldByReceiver = autoreleasepool { weakViewController != nil }
        XCTAssertTrue(heldByReceiver, file: file, line: line)

        dropped.signal()
        PerformanceMonitoring.consumerQueue.sync { }
        let survived = autoreleasepool { weakViewController != nil }

        waitUntilDeallocated({ weakViewController == nil }, file: file, line: line)
        XCTAssertEqual(receiver.methods, [callback.receiverMethod], file: file, line: line)
        XCTAssertEqual(receiver.loadedViewControllers, 1, file: file, line: line)
        return survived
    }

    private func waitUntilDeallocated(_ isDeallocated: () -> Bool, file: StaticString = #filePath, line: UInt = #line) {
        let deadline = Date().addingTimeInterval(2)
        while !isDeallocated() && Date() < deadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.01))
        }
        XCTAssertTrue(isDeallocated(), file: file, line: line)
    }
}

private enum LoggingCallback: CaseIterable {
    case beforeInit, beforeViewDidLoad, afterViewWillAppear, afterViewDidAppear, beforeViewWillDisappear

    func call(_ observer: ViewControllerObserver, _ viewController: UIViewController) {
        switch self {
        case .beforeInit: observer.beforeInit(viewController: viewController)
        case .beforeViewDidLoad: observer.beforeViewDidLoad(viewController: viewController)
        case .afterViewWillAppear: observer.afterViewWillAppear(viewController: viewController)
        case .afterViewDidAppear: observer.afterViewDidAppear(viewController: viewController)
        case .beforeViewWillDisappear: observer.beforeViewWillDisappear(viewController: viewController)
        }
    }

    var receiverMethod: String {
        switch self {
        case .beforeInit: return "onInit"
        case .beforeViewDidLoad: return "onViewDidLoad"
        case .afterViewWillAppear: return "onViewWillAppear"
        case .afterViewDidAppear: return "onViewDidAppear"
        case .beforeViewWillDisappear: return "onViewWillDisappear"
        }
    }
}

/// Holds its view controller weakly, like a production screen identifier.
private final class WeakScreen {
    init(viewController: UIViewController) {
        self.viewController = viewController
    }

    weak var viewController: UIViewController?
}

/// Loads the view controller from the screen identifier in every callback, like a receiver that needs it.
private final class ViewControllerLoadingReceiver: ViewControllerLoggingReceiver {
    // Mutated on consumerQueue; the test reads them after `consumerQueue.sync { }`.
    private(set) var methods: [String] = []
    private(set) var loadedViewControllers = 0
    /// Called on consumerQueue while the receiver holds the view controller it loaded. Set before any callback.
    var whileHoldingViewController: (() -> Void)?
    /// Whether the receiver also autoreleases the view controller it loaded. Set before any callback.
    var autoreleasesViewController = false

    func screenIdentifier(for viewController: UIViewController) -> WeakScreen? {
        return WeakScreen(viewController: viewController)
    }

    func onInit(screen: WeakScreen) { received("onInit", screen) }
    func onViewDidLoad(screen: WeakScreen) { received("onViewDidLoad", screen) }
    func onViewWillAppear(screen: WeakScreen) { received("onViewWillAppear", screen) }
    func onViewDidAppear(screen: WeakScreen) { received("onViewDidAppear", screen) }
    func onViewWillDisappear(screen: WeakScreen) { received("onViewWillDisappear", screen) }

    private func received(_ method: String, _ screen: WeakScreen) {
        methods.append(method)
        guard let viewController = screen.viewController else {
            return
        }
        loadedViewControllers += 1
        if autoreleasesViewController {
            _ = Unmanaged.passRetained(viewController).autorelease()
        }
        withExtendedLifetime(viewController) {
            whileHoldingViewController?()
        }
    }
}

class LoggingReceiverStub: ViewControllerLoggingReceiver {
    func screenIdentifier(for viewController: UIViewController) -> String? {
        self.viewController = viewController
        return viewController.description
    }

    func onInit(screen viewControllerKey: String) {
        self.method = "onInit"
        self.key = viewControllerKey
    }

    func onViewDidLoad(screen viewControllerKey: String) {
        self.method = "onViewDidLoad"
        self.key = viewControllerKey
    }

    func onViewWillAppear(screen viewControllerKey: String) {
        self.method = "onViewWillAppear"
        self.key = viewControllerKey
    }

    func onViewDidAppear(screen viewControllerKey: String) {
        self.method = "onViewDidAppear"
        self.key = viewControllerKey
    }

    func onViewWillDisappear(screen viewControllerKey: String) {
        self.method = "onViewWillDisappear"
        self.key = viewControllerKey
    }

    func onViewDidDisappear(screen viewControllerKey: String) {
        self.method = "onViewDidDisappear"
        self.key = viewControllerKey
    }

    func clear() {
        method = nil
        viewController = nil
        key = nil
    }

    var method: String?
    var viewController: UIViewController?
    var key: String?

}
