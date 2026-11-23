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
        viewController = nil
        PerformanceMonitoring.queue.sync { }

        XCTAssertEqual(observers.count, 1)
        XCTAssertEqual(observers.first?.methods, [.beforeInit, .beforeViewDidLoad, .afterViewWillAppear, .afterViewDidAppear, .beforeViewWillDisappear])
        // Every queue item has finished, but the view controller is only released by the items queued on main.
        XCTAssertNotNil(weakViewController)
        waitUntilDeallocated { weakViewController == nil }
    }

    private func waitUntilDeallocated(_ isDeallocated: () -> Bool, file: StaticString = #filePath, line: UInt = #line) {
        let deadline = Date().addingTimeInterval(2)
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
