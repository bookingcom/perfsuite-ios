//
//  ViewControllerObserverTests.swift
//  PerformanceSuite
//
//  Created by Gleb Tarasov on 06/07/2021.
//

import SwiftUI
import XCTest

@testable import PerformanceSuite

class ViewControllerObserverTests: XCTestCase {

    override func tearDown() {
        super.tearDown()
        PerformanceMonitoring.consumerQueue.sync { }
        PerformanceMonitoring.queue.sync { }
    }

    func testObserversCollection() {
        let o1 = Observer()
        let o2 = Observer()
        let collection = ViewControllerObserverCollection(observers: [o1, o2])

        let vc = UIViewController()

        collection.beforeInit(viewController: vc)

        XCTAssertEqual(o1.viewController, vc)
        XCTAssertEqual(o1.lastMethod, .beforeInit)

        XCTAssertEqual(o2.viewController, vc)
        XCTAssertEqual(o2.lastMethod, .beforeInit)

        o1.clear()
        o2.clear()

        collection.afterViewDidAppear(viewController: vc)

        XCTAssertEqual(o1.viewController, vc)
        XCTAssertEqual(o1.lastMethod, .afterViewDidAppear)

        XCTAssertEqual(o2.viewController, vc)
        XCTAssertEqual(o2.lastMethod, .afterViewDidAppear)

        o1.clear()
        o2.clear()

        collection.afterViewWillAppear(viewController: vc)

        XCTAssertEqual(o1.viewController, vc)
        XCTAssertEqual(o1.lastMethod, .afterViewWillAppear)

        XCTAssertEqual(o2.viewController, vc)
        XCTAssertEqual(o2.lastMethod, .afterViewWillAppear)

        o1.clear()
        o2.clear()

        collection.beforeViewWillDisappear(viewController: vc)

        XCTAssertEqual(o1.viewController, vc)
        XCTAssertEqual(o1.lastMethod, .beforeViewWillDisappear)

        XCTAssertEqual(o2.viewController, vc)
        XCTAssertEqual(o2.lastMethod, .beforeViewWillDisappear)

        o1.clear()
        o2.clear()

        collection.beforeViewDidDisappear(viewController: vc)

        XCTAssertEqual(o1.viewController, vc)
        XCTAssertEqual(o1.lastMethod, .beforeViewDidDisappear)

        XCTAssertEqual(o2.viewController, vc)
        XCTAssertEqual(o2.lastMethod, .beforeViewDidDisappear)
    }

    func testObserversFactory() {
        let factory = ViewControllerObserverFactory<InstanceObserver, TTIMetricsReceiverStub>(metricsReceiver: TTIMetricsReceiverStub()) { vc in
            InstanceObserver(viewController: vc)
        }

        lastObserverCreated = nil

        let vc1 = MyViewController()
        factory.beforeInit(viewController: vc1)
        PerformanceMonitoring.queue.sync { }

        let observer = lastObserverCreated
        XCTAssertNotNil(observer)
        XCTAssertEqual(observer?.lastMethod, .beforeInit)
        XCTAssertEqual(observer?.viewController, vc1)

        observer?.clear()
        lastObserverCreated = nil

        factory.afterViewDidAppear(viewController: vc1)
        PerformanceMonitoring.queue.sync { }

        XCTAssertNil(lastObserverCreated)
        XCTAssertEqual(observer?.lastMethod, .afterViewDidAppear)
        XCTAssertEqual(observer?.viewController, vc1)
        observer?.clear()


        let vc2 = MyViewController()
        factory.afterViewDidAppear(viewController: vc2)
        PerformanceMonitoring.queue.sync { }

        XCTAssertNotNil(lastObserverCreated)
        XCTAssert(lastObserverCreated !== observer)
        XCTAssertEqual(lastObserverCreated?.lastMethod, .afterViewDidAppear)
        XCTAssertEqual(lastObserverCreated?.viewController, vc2)
        lastObserverCreated?.clear()

        factory.beforeViewWillDisappear(viewController: vc2)
        PerformanceMonitoring.queue.sync { }

        XCTAssertNotNil(lastObserverCreated)
        let observer2 = lastObserverCreated
        XCTAssertEqual(observer2?.lastMethod, .beforeViewWillDisappear)
        XCTAssertEqual(observer2?.viewController, vc2)
        observer2?.clear()
        lastObserverCreated = nil

        factory.afterViewWillAppear(viewController: vc1)
        PerformanceMonitoring.queue.sync { }

        XCTAssertNil(lastObserverCreated)
        XCTAssertEqual(observer?.lastMethod, .afterViewWillAppear)
        XCTAssertEqual(observer?.viewController, vc1)

        factory.beforeViewDidDisappear(viewController: vc2)
        PerformanceMonitoring.queue.sync { }

        XCTAssertNil(lastObserverCreated)
        // beforeViewDidDisappear is not supported in instance observers, only in observers, that's why it shouldn't change anything
        XCTAssertNil(observer2?.lastMethod)
        XCTAssertEqual(observer2?.viewController, vc2)
    }

    func testSwiftUIHostingControllerIsIgnored() {
        let metricsReceiver = MetricsConsumerForSwiftUITest()
        let factory = ViewControllerObserverFactory<InstanceObserver, MetricsConsumerForSwiftUITest>(metricsReceiver: metricsReceiver) { vc in
            InstanceObserver(viewController: vc)
        }

        lastObserverCreated = nil

        let vc1 = UIHostingController(rootView: Text("123"))
        factory.beforeInit(viewController: vc1)
        XCTAssertNil(lastObserverCreated)
        factory.afterViewWillAppear(viewController: vc1)
        factory.afterViewDidAppear(viewController: vc1)
        factory.beforeViewWillDisappear(viewController: vc1)
        XCTAssertNil(lastObserverCreated)
    }

    func testAsyncReleasingOnMainReleasesOnMainWhenMainRunsBeforeWorkEnds() {
        var viewController: MyViewController? = MyViewController()
        weak var weakViewController = viewController
        let workStarted = DispatchSemaphore(value: 0)
        let mainDrained = DispatchSemaphore(value: 0)

        PerformanceMonitoring.queue.asyncReleasingOnMain(viewController!) { _ in
            workStarted.signal()
            // The queue thread is preempted here: main runs everything it has before the work ends.
            mainDrained.wait()
        }
        workStarted.wait()
        viewController = nil
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        XCTAssertNotNil(weakViewController)

        mainDrained.signal()
        waitUntilDeallocated { weakViewController == nil }
        // MyViewController.deinit asserts that it runs on the main thread.
    }

    func testFactoryReleasesViewControllerOnMainWithReleaseViewControllersOnMain() {
        PerformanceMonitoring.experiments = Experiments(releaseViewControllersOnMain: true)
        defer {
            PerformanceMonitoring.experiments = Experiments()
        }
        var observers: [MethodsRecordingObserver] = []
        let factory = ViewControllerObserverFactory<MethodsRecordingObserver, StringScreenReceiver>(metricsReceiver: StringScreenReceiver()) { _ in
            let observer = MethodsRecordingObserver()
            observers.append(observer)
            return observer
        }

        var viewController: MyViewController? = MyViewController()
        weak var weakViewController = viewController
        factory.beforeInit(viewController: viewController!)
        factory.beforeViewDidLoad(viewController: viewController!)
        factory.afterViewWillAppear(viewController: viewController!)
        factory.afterViewDidAppear(viewController: viewController!)
        factory.beforeViewWillDisappear(viewController: viewController!)
        PerformanceMonitoring.queue.sync { }
        viewController = nil

        XCTAssertEqual(observers.count, 1)
        XCTAssertEqual(observers.first?.methods, [.beforeInit, .beforeViewDidLoad, .afterViewWillAppear, .afterViewDidAppear, .beforeViewWillDisappear])
        // Every queue item has finished, but its retain is released by a block queued on main.
        XCTAssertNotNil(weakViewController)
        waitUntilDeallocated { weakViewController == nil }
    }

    func testAsyncReleasingOnMainDoesNotRetainQueuedViewController() {
        let queueGate = DispatchSemaphore(value: 0)
        addTeardownBlock { queueGate.signal() }
        PerformanceMonitoring.queue.async { queueGate.wait() }
        var workRan = false

        var viewController: MyViewController? = MyViewController()
        weak var weakViewController = viewController
        PerformanceMonitoring.queue.asyncReleasingOnMain(viewController!) { _ in workRan = true }
        viewController = nil

        // A queue backlog must not delay the deallocation, or leak detection could report it.
        XCTAssertNil(weakViewController)
        queueGate.signal()
        PerformanceMonitoring.queue.sync { }
        XCTAssertFalse(workRan)
    }

    func testFactoryRetainsMappedScreenWhileCreatingObserverWithReleaseViewControllersOnMain() {
        PerformanceMonitoring.experiments = Experiments(releaseViewControllersOnMain: true)
        defer {
            PerformanceMonitoring.experiments = Experiments()
        }
        let screen = MyViewController()
        let receiver = MappedScreenLoggingReceiver()
        receiver.screen = { [weak screen] in screen }
        let factory = ViewControllerObserverFactory<MethodsRecordingObserver, MappedScreenLoggingReceiver>(metricsReceiver: receiver) { _ in
            MethodsRecordingObserver()
        }

        // The screen returned by `screenIdentifier(for:)` can be another view controller that only the factory still
        // references; the factory must hand that reference to main instead of releasing it itself.
        let (observer, screenReferences) = factory.makeObserver(for: MyViewController())
        XCTAssertNotNil(observer)
        XCTAssertEqual(screenReferences.map { $0.takeUnretainedValue() }, [screen])
        screenReferences.forEach { $0.release() }
    }

    func testInstanceObserverKeepsReceiverFromReleasingMappedScreenLastWithReleaseViewControllersOnMain() {
        PerformanceMonitoring.experiments = Experiments(releaseViewControllersOnMain: true)
        defer {
            PerformanceMonitoring.experiments = Experiments()
        }
        let receiver = MappedScreenLoggingReceiver()
        let factory = ViewControllerObserverFactory<LoggingObserver<MappedScreenLoggingReceiver>, MappedScreenLoggingReceiver>(
            metricsReceiver: receiver
        ) {
            LoggingObserver(screen: $0, receiver: receiver)
        }
        let viewController = MyViewController()

        assertReceiverDoesNotReleaseViewControllerLast { screen, receiverWork in
            receiver.screen = { [weak screen] in screen }
            receiver.onViewDidAppear = { receivedScreen in
                receiverWork { [weak receivedScreen] in receivedScreen }
            }
            factory.afterViewDidAppear(viewController: viewController)
        }
    }

    func testRetainingViewControllerKeepsReceiverFromReleasingItLast() {
        PerformanceMonitoring.experiments = Experiments(releaseViewControllersOnMain: true)
        defer {
            PerformanceMonitoring.experiments = Experiments()
        }
        assertReceiverDoesNotReleaseViewControllerLast { viewController, receiverWork in
            PerformanceMonitoring.consumerQueue.async { [weak viewController] in
                retainingViewController({ viewController }, during: {
                    receiverWork { viewController }
                })
            }
        }
    }

    func testReceiverIdentifierRetainsReferencedViewControllerOfViewControllerIdentifier() {
        PerformanceMonitoring.experiments = Experiments(releaseViewControllersOnMain: true)
        defer {
            PerformanceMonitoring.experiments = Experiments()
        }
        let identifierViewController = ReferencingViewController()
        let referencedViewController = MyViewController()
        identifierViewController.referenced = referencedViewController

        let identifier = ReceiverIdentifier<UIViewController>(identifierViewController)
        XCTAssertTrue(identifier.viewControllers.contains { $0 === referencedViewController })
    }

    func testReceiverIdentifierRetainsReferencedViewControllerAfterViewControllerIdentifierIsGone() throws {
        PerformanceMonitoring.experiments = Experiments(releaseViewControllersOnMain: true)
        defer {
            PerformanceMonitoring.experiments = Experiments()
        }
        let referencedViewController = MyViewController()
        weak var weakIdentifierViewController: ReferencingViewController?
        let identifier: ReceiverIdentifier<UIViewController> = autoreleasepool {
            let identifierViewController = ReferencingViewController()
            identifierViewController.referenced = referencedViewController
            weakIdentifierViewController = identifierViewController
            return ReceiverIdentifier(identifierViewController)
        }
        try XCTSkipIf(weakIdentifierViewController != nil, "UIKit kept the identifier view controller alive")

        // A measurement handle's cancel can still load the referenced view controller.
        XCTAssertTrue(identifier.viewControllers.contains { $0 === referencedViewController })
    }

    func testInstanceObserverKeepsReceiverFromReleasingViewControllerLastWithReleaseViewControllersOnMain() {
        PerformanceMonitoring.experiments = Experiments(releaseViewControllersOnMain: true)
        defer {
            PerformanceMonitoring.experiments = Experiments()
        }
        let receiver = WeakScreenLoggingReceiver()
        let factory = ViewControllerObserverFactory<LoggingObserver<WeakScreenLoggingReceiver>, WeakScreenLoggingReceiver>(
            metricsReceiver: receiver
        ) {
            LoggingObserver(screen: $0, receiver: receiver)
        }

        assertReceiverDoesNotReleaseViewControllerLast { viewController, receiverWork in
            receiver.onViewDidAppear = receiverWork
            factory.afterViewDidAppear(viewController: viewController)
        }
    }

    func testInstanceObserverDoesNotRetainViewControllerScreenWithReleaseViewControllersOnMain() {
        PerformanceMonitoring.experiments = Experiments(releaseViewControllersOnMain: true)
        defer {
            PerformanceMonitoring.experiments = Experiments()
        }
        let receiver = ViewControllerScreenLoggingReceiver()
        let factory = ViewControllerObserverFactory<LoggingObserver<ViewControllerScreenLoggingReceiver>, ViewControllerScreenLoggingReceiver>(
            metricsReceiver: receiver
        ) {
            LoggingObserver(screen: $0, receiver: receiver)
        }

        var viewController: MyViewController? = MyViewController()
        weak var weakViewController = viewController
        factory.beforeInit(viewController: viewController!)
        factory.afterViewDidAppear(viewController: viewController!)
        PerformanceMonitoring.queue.sync { }
        PerformanceMonitoring.consumerQueue.sync { }
        viewController = nil

        XCTAssertEqual(receiver.appearedScreens, 1)
        // The view controller retains its observer, which must not retain it back.
        waitUntilDeallocated { weakViewController == nil }
    }

    /// `schedule` must run `receiverWork` on the consumer queue like a receiver call, with a loader of a weak reference to the
    /// view controller. Once the receiver has loaded it into a strong temporary, main drops every other reference and drains
    /// its queue before the receiver returns.
    private func assertReceiverDoesNotReleaseViewControllerLast(
        file: StaticString = #filePath,
        line: UInt = #line,
        _ schedule: (MyViewController, @escaping (_ load: () -> UIViewController?) -> Void) -> Void
    ) {
        var viewController: MyViewController? = MyViewController()
        weak var weakViewController = viewController
        let loaded = DispatchSemaphore(value: 0)
        let receiverMayReturn = DispatchSemaphore(value: 0)
        var loadedViewController = false

        schedule(viewController!) { load in
            let strongViewController = load()
            loadedViewController = strongViewController != nil
            loaded.signal()
            receiverMayReturn.wait()
            withExtendedLifetime(strongViewController) {}
        }
        prioritizeConsumerQueue()
        guard loaded.wait(timeout: .now() + 30) == .success else {
            receiverMayReturn.signal()
            XCTFail("The receiver was not called", file: file, line: line)
            return
        }
        viewController = nil
        PerformanceMonitoring.queue.sync { }
        let mainDrained = expectation(description: "mainDrained")
        DispatchQueue.main.async { mainDrained.fulfill() }
        wait(for: [mainDrained], timeout: 5)
        receiverMayReturn.signal()
        PerformanceMonitoring.consumerQueue.sync { }

        XCTAssertTrue(loadedViewController, file: file, line: line)
        // The receiver's temporary was not the last reference: the last one is released by a block queued on main.
        XCTAssertNotNil(weakViewController, file: file, line: line)
        waitUntilDeallocated(file: file, line: line) { weakViewController == nil }
        // MyViewController.deinit asserts that it runs on the main thread.
    }

    private func waitUntilDeallocated(file: StaticString = #filePath, line: UInt = #line, _ isDeallocated: () -> Bool) {
        // A release can wait for the background-QoS consumer queue, which can be slow on a busy simulator.
        let deadline = Date().addingTimeInterval(10)
        while !isDeallocated() && Date() < deadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.01))
        }
        XCTAssertTrue(isDeallocated(), file: file, line: line)
    }
}

private final class StringScreenReceiver: ScreenMetricsReceiver {
    func screenIdentifier(for viewController: UIViewController) -> String? {
        return String(describing: type(of: viewController))
    }
}

private final class WeakScreen {
    weak var viewController: UIViewController?
    init(_ viewController: UIViewController) { self.viewController = viewController }
}

private final class WeakScreenLoggingReceiver: ViewControllerLoggingReceiver {
    var onViewDidAppear: ((_ load: () -> UIViewController?) -> Void)?

    func screenIdentifier(for viewController: UIViewController) -> WeakScreen? {
        return WeakScreen(viewController)
    }

    func onInit(screen: WeakScreen) {}
    func onViewDidLoad(screen: WeakScreen) {}
    func onViewWillAppear(screen: WeakScreen) {}
    func onViewDidAppear(screen: WeakScreen) {
        onViewDidAppear? { screen.viewController }
    }
    func onViewWillDisappear(screen: WeakScreen) {}
}

private final class ReferencingViewController: UIViewController, ViewControllerReferencing {
    weak var referenced: UIViewController?

    var referencedViewController: UIViewController? {
        return referenced
    }
}

private final class MappedScreenLoggingReceiver: ViewControllerLoggingReceiver {
    var screen: (() -> UIViewController?)?
    var onViewDidAppear: ((UIViewController) -> Void)?

    func screenIdentifier(for viewController: UIViewController) -> UIViewController? {
        return screen?()
    }

    func onInit(screen: UIViewController) {}
    func onViewDidLoad(screen: UIViewController) {}
    func onViewWillAppear(screen: UIViewController) {}
    func onViewDidAppear(screen: UIViewController) {
        onViewDidAppear?(screen)
    }
    func onViewWillDisappear(screen: UIViewController) {}
}

private final class ViewControllerScreenLoggingReceiver: ViewControllerLoggingReceiver {
    private(set) var appearedScreens = 0

    func screenIdentifier(for viewController: UIViewController) -> UIViewController? {
        return viewController
    }

    func onInit(screen: UIViewController) {}
    func onViewDidLoad(screen: UIViewController) {}
    func onViewWillAppear(screen: UIViewController) {}
    func onViewDidAppear(screen: UIViewController) {
        appearedScreens += 1
    }
    func onViewWillDisappear(screen: UIViewController) {}
}

private final class MethodsRecordingObserver: ViewControllerInstanceObserver {
    static let identifier: AnyObject = NSObject()
    private(set) var methods: [ObserverMethods] = []

    func beforeInit() { methods.append(.beforeInit) }
    func beforeViewDidLoad() { methods.append(.beforeViewDidLoad) }
    func afterViewWillAppear() { methods.append(.afterViewWillAppear) }
    func afterViewDidAppear() { methods.append(.afterViewDidAppear) }
    func beforeViewWillDisappear() { methods.append(.beforeViewWillDisappear) }
}

private class MetricsConsumerForSwiftUITest: ScreenMetricsReceiver {
    func ttiMetricsReceived(metrics: TTIMetrics, screen: UIViewController) {}
    func renderingMetricsReceived(metrics: RenderingMetrics, screen: UIViewController) {}
    func appRenderingMetricsReceived(metrics: RenderingMetrics) {}
}

private class MyViewController: UIViewController {
    deinit {
        XCTAssertTrue(Thread.isMainThread)
    }
}
