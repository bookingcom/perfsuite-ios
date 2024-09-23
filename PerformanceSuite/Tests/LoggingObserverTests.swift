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
        let vc = UIViewController()
        let observer = LoggingObserver(screen: "view controller", receiver: stub)

        XCTAssertNil(stub.method)
        XCTAssertNil(stub.viewController)

        observer.beforeInit(viewController: vc)
        PerformanceMonitoring.consumerQueue.sync {}
        XCTAssertEqual(stub.method, "onInit")
        XCTAssertEqual(stub.key, "view controller")
        stub.clear()

        observer.beforeViewDidLoad(viewController: vc)
        PerformanceMonitoring.consumerQueue.sync {}
        XCTAssertEqual(stub.method, "onViewDidLoad")
        XCTAssertEqual(stub.key, "view controller")
        stub.clear()

        observer.afterViewWillAppear(viewController: vc)
        PerformanceMonitoring.consumerQueue.sync {}
        XCTAssertEqual(stub.method, "onViewWillAppear")
        XCTAssertEqual(stub.key, "view controller")
        stub.clear()

        observer.afterViewDidAppear(viewController: vc)
        PerformanceMonitoring.consumerQueue.sync {}
        XCTAssertEqual(stub.method, "onViewDidAppear")
        XCTAssertEqual(stub.key, "view controller")
        stub.clear()

        observer.beforeViewWillDisappear(viewController: vc)
        PerformanceMonitoring.consumerQueue.sync {}
        XCTAssertEqual(stub.method, "onViewWillDisappear")
        XCTAssertEqual(stub.key, "view controller")
        stub.clear()

        observer.beforeViewDidDisappear(viewController: vc)
        PerformanceMonitoring.consumerQueue.sync {}
        XCTAssertEqual(stub.method, "onViewDidDisappear")
        XCTAssertEqual(stub.key, "view controller")
        stub.clear()
    }

    func testRuntimeInfoIsSaved() {
        AppInfoHolder.resetForTests()

        let stub = LoggingReceiverStub()
        let vcs = [
            UIViewController(), // ignored, UIKit
            UIHostingController(rootView: MyViewForLoggingObserverTests()), // take
            UINavigationController(rootViewController: UIViewController()), // ignored, UIKit
            MyViewController1(), // take
            UIPageViewController(), // ignored, container
            MyViewController2(), // ignored, container
            MyViewController3(rootView: MyView3()), // take

        ]
        _ = vcs.compactMap {
            if let screen = stub.screenIdentifier(for: $0) {
                let o = LoggingObserver(screen: screen, receiver: stub)
                o.afterViewDidAppear(viewController: $0)
                return o
            } else {
                return nil
            }

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
            "MyViewForLoggingObserverTests",
            "MyViewController1",
            "MyView3",
        ])
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

private class MyViewController1: UIViewController { }
private class MyViewController2: UIPageViewController { }

private struct MyView3: View {
    var body: some View { return Text("blabla") }
}
private class MyViewController3: UIHostingController<MyView3> { }

// it shouldn't be private to have non-random type description
struct MyViewForLoggingObserverTests: View {
    var body: some View { return Text("blabla") }
}
