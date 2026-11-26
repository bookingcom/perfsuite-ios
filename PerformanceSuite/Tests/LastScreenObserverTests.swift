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
        checkRuntimeInfoIsSaved()
    }

    func testRuntimeInfoIsSavedWithReleaseViewControllersOnMain() {
        PerformanceMonitoring.experiments = Experiments(releaseViewControllersOnMain: true)
        defer {
            PerformanceMonitoring.experiments = Experiments()
        }
        checkRuntimeInfoIsSaved()
    }

    private func checkRuntimeInfoIsSaved() {
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

    func testViewControllerIsReleasedOnMainWithReleaseViewControllersOnMain() {
        PerformanceMonitoring.experiments = Experiments(releaseViewControllersOnMain: true)
        addTeardownBlock { PerformanceMonitoring.experiments = Experiments() }
        AppInfoHolder.resetForTests()
        let queueGate = DispatchSemaphore(value: 0)
        addTeardownBlock { queueGate.signal() }
        PerformanceMonitoring.queue.async { queueGate.wait() }
        let observer = LastOpenedScreenObserver()
        var viewController: MyViewController1? = MyViewController1()
        weak var weakViewController = viewController

        observer.afterViewDidAppear(viewController: viewController!)
        let mainDrained = expectation(description: "mainDrained")
        DispatchQueue.main.async { mainDrained.fulfill() }
        wait(for: [mainDrained], timeout: 5)
        viewController = nil

        // The queued description borrows the view controller, so it is alive while the queue works.
        XCTAssertNotNil(weakViewController)
        queueGate.signal()
        PerformanceMonitoring.queue.sync { }
        XCTAssertEqual(AppInfoHolder.appRuntimeInfo.openedScreens, ["MyViewController1"])
        // The queue is done and did not release it: the last reference is released on main.
        // (A view controller's dealloc thread proves nothing, UIKit defers dealloc to main.)
        XCTAssertNotNil(weakViewController)
        // UIKit can keep an extra retain for a moment, so poll the main run loop instead of a single main turn.
        let deadline = Date().addingTimeInterval(2)
        while weakViewController != nil && Date() < deadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.01))
        }
        XCTAssertNil(weakViewController)
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
