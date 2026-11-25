//
//  LastScreenObserverTests.swift
//  Pods
//
//  Created by Gleb Tarasov on 19/10/2024.
//

import XCTest
import SwiftUI
import UIKit
@testable import PerformanceSuite

final class LastScreenObserverTests: XCTestCase {

    func testRuntimeInfoIsSaved() {
        AppInfoHolder.resetForTests()
        let vcs = [
            UIViewController(), // ignored, UIKit
            UIHostingController(rootView: MyViewForLastScreenObserverTests()), // take
            UINavigationController(rootViewController: UIViewController()), // ignored, UIKit
            MyViewController1(), // take
            UIPageViewController(), // ignored, container
            MyViewController2(), // ignored, container
            MyViewController3(rootView: MyView3()), // take

        ]
        _ = vcs.compactMap {
            let o = LastOpenedScreenObserver()
            o.afterViewDidAppear(viewController: $0)
            return o
        }

        let exp = expectation(description: "openedScreens")

        DispatchQueue.global().async {
            while AppInfoHolder.appRuntimeInfo.openedScreens.count < 3 {
                Thread.sleep(forTimeInterval: 0.001)
            }
            exp.fulfill()
        }

        wait(for: [exp], timeout: 5)

        XCTAssertEqual(AppInfoHolder.appRuntimeInfo.openedScreens, [
            "MyViewForLastScreenObserverTests",
            "MyViewController1",
            "MyView3",
        ])
    }

    func testViewControllerIsNotPassedToQueueWithReleaseViewControllersOnMain() {
        PerformanceMonitoring.experiments = Experiments(releaseViewControllersOnMain: true)
        defer {
            PerformanceMonitoring.experiments = Experiments()
        }
        AppInfoHolder.resetForTests()
        let queueGate = DispatchSemaphore(value: 0)
        addTeardownBlock { queueGate.signal() }
        PerformanceMonitoring.queue.async { queueGate.wait() }
        let observer = LastOpenedScreenObserver()
        var viewController: MainThreadDeallocatedViewController? = MainThreadDeallocatedViewController()
        weak var weakViewController = viewController

        observer.afterViewDidAppear(viewController: viewController!)
        let mainDrained = expectation(description: "mainDrained")
        DispatchQueue.main.async { mainDrained.fulfill() }
        wait(for: [mainDrained], timeout: 5)
        viewController = nil

        // The top screen check on main has run; nothing queued on PerformanceMonitoring.queue holds the view controller.
        XCTAssertNil(weakViewController)
        queueGate.signal()
        PerformanceMonitoring.queue.sync { }
        XCTAssertEqual(AppInfoHolder.appRuntimeInfo.openedScreens, ["MainThreadDeallocatedViewController"])
    }

    func testDeferredTopScreenCheckDoesNotRetainViewControllerWithReleaseViewControllersOnMain() {
        PerformanceMonitoring.experiments = Experiments(releaseViewControllersOnMain: true)
        defer {
            PerformanceMonitoring.experiments = Experiments()
        }
        AppInfoHolder.resetForTests()
        let observer = LastOpenedScreenObserver()
        var viewController: MainThreadDeallocatedViewController? = MainThreadDeallocatedViewController()
        weak var weakViewController = viewController

        observer.afterViewDidAppear(viewController: viewController!)
        viewController = nil

        // The check is still queued on main; it must not keep the view controller alive past a leak check.
        XCTAssertNil(weakViewController)
        let mainDrained = expectation(description: "mainDrained")
        DispatchQueue.main.async { mainDrained.fulfill() }
        wait(for: [mainDrained], timeout: 5)
        PerformanceMonitoring.queue.sync { }
        XCTAssertEqual(AppInfoHolder.appRuntimeInfo.openedScreens, [])
    }
}

private class MainThreadDeallocatedViewController: UIViewController {
    deinit {
        XCTAssertTrue(Thread.isMainThread)
    }
}

private class MyViewController1: UIViewController { }
private class MyViewController2: UIPageViewController { }

private struct MyView3: View {
    var body: some View { return Text("blabla") }
}
private class MyViewController3: UIHostingController<MyView3> { }

// it shouldn't be private to have non-random type description
struct MyViewForLastScreenObserverTests: View {
    var body: some View { return Text("blabla") }
}
