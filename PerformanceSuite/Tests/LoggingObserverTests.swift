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
        PerformanceSuite.experiments = Experiments(ios_adq_no_locks_in_main_thread_call_stack: 1)
        let stub = LoggingReceiverStub()
        let observer = LoggingObserver(receiver: stub)
        let vc = UIViewController()

        XCTAssertNil(stub.method)
        XCTAssertNil(stub.viewController)

        observer.beforeInit(viewController: vc)
        PerformanceSuite.consumerQueue.sync {}
        XCTAssertEqual(stub.method, "onInit")
        XCTAssertEqual(stub.viewController, vc)
        XCTAssertEqual(stub.key, vc.description)
        stub.clear()

        observer.beforeViewDidLoad(viewController: vc)
        PerformanceSuite.consumerQueue.sync {}
        XCTAssertEqual(stub.method, "onViewDidLoad")
        XCTAssertEqual(stub.viewController, vc)
        XCTAssertEqual(stub.key, vc.description)
        stub.clear()

        observer.afterViewWillAppear(viewController: vc)
        PerformanceSuite.consumerQueue.sync {}
        XCTAssertEqual(stub.method, "onViewWillAppear")
        XCTAssertEqual(stub.viewController, vc)
        XCTAssertEqual(stub.key, vc.description)
        stub.clear()

        observer.afterViewDidAppear(viewController: vc)
        PerformanceSuite.consumerQueue.sync {}
        XCTAssertEqual(stub.method, "onViewDidAppear")
        XCTAssertEqual(stub.viewController, vc)
        XCTAssertEqual(stub.key, vc.description)
        stub.clear()

        observer.beforeViewWillDisappear(viewController: vc)
        PerformanceSuite.consumerQueue.sync {}
        XCTAssertEqual(stub.method, "onViewWillDisappear")
        XCTAssertEqual(stub.viewController, vc)
        XCTAssertEqual(stub.key, vc.description)
        stub.clear()

        observer.beforeViewDidDisappear(viewController: vc)
        PerformanceSuite.consumerQueue.sync {}
        XCTAssertEqual(stub.method, "onViewDidDisappear")
        XCTAssertEqual(stub.viewController, vc)
        XCTAssertEqual(stub.key, vc.description)
        stub.clear()
        PerformanceSuite.experiments = Experiments()
    }

    func testRuntimeInfoIsSavedV1() {
        PerformanceSuite.experiments = Experiments(ios_adq_add_screen_information_to_termination_squeaks: 1)
        AppInfoHolder.resetForTests()

        let stub = LoggingReceiverStub()
        let observer = LoggingObserver(receiver: stub)
        let vcs = [
            UIViewController(), // ignored, UIKit
            UIHostingController(rootView: MyViewForLoggingObserverTests()), // take
            UINavigationController(rootViewController: UIViewController()), // ignored, UIKit
            MyViewController1(), // take
            UIPageViewController(), // ignored, container
            MyViewController2(), // ignored, container
            MyViewController3(rootView: MyView3()), // take

        ]
        vcs.forEach { observer.afterViewDidAppear(viewController: $0) }

        XCTAssertEqual(AppInfoHolder.appRuntimeInfo.openedScreens, [
            "_TtGC7SwiftUI19UIHostingControllerV27PerformanceSuite_Unit_Tests29MyViewForLoggingObserverTests_",
            "_TtC27PerformanceSuite_Unit_TestsP33_ACF6D520A1CF33499E18FE4EF54EC1EC17MyViewController1",
            "_TtC27PerformanceSuite_Unit_TestsP33_ACF6D520A1CF33499E18FE4EF54EC1EC17MyViewController3",
        ])

        PerformanceSuite.experiments = Experiments()
    }

    func testRuntimeInfoIsSavedV2() {
        PerformanceSuite.experiments = Experiments(ios_adq_add_screen_information_to_termination_squeaks: 2)
        AppInfoHolder.resetForTests()

        let stub = LoggingReceiverStub()
        let observer = LoggingObserver(receiver: stub)
        let vcs = [
            UIViewController(), // ignored, UIKit
            UIHostingController(rootView: MyViewForLoggingObserverTests()), // take
            UINavigationController(rootViewController: UIViewController()), // ignored, UIKit
            MyViewController1(), // take
            UIPageViewController(), // ignored, container
            MyViewController2(), // ignored, container
            MyViewController3(rootView: MyView3()), // take

        ]
        vcs.forEach { observer.afterViewDidAppear(viewController: $0) }

        XCTAssertEqual(AppInfoHolder.appRuntimeInfo.openedScreens, [
            "MyViewForLoggingObserverTests",
            "_TtC27PerformanceSuite_Unit_TestsP33_ACF6D520A1CF33499E18FE4EF54EC1EC17MyViewController1",
            "MyView3",
        ])

        PerformanceSuite.experiments = Experiments()
    }
}

class LoggingReceiverStub: ViewControllerLoggingReceiver {
    func key(for viewController: UIViewController) -> String {
        self.viewController = viewController
        return viewController.description
    }

    func onInit(viewControllerKey: String) {
        self.method = "onInit"
        self.key = viewControllerKey
    }

    func onViewDidLoad(viewControllerKey: String) {
        self.method = "onViewDidLoad"
        self.key = viewControllerKey
    }

    func onViewWillAppear(viewControllerKey: String) {
        self.method = "onViewWillAppear"
        self.key = viewControllerKey
    }

    func onViewDidAppear(viewControllerKey: String) {
        self.method = "onViewDidAppear"
        self.key = viewControllerKey
    }

    func onViewWillDisappear(viewControllerKey: String) {
        self.method = "onViewWillDisappear"
        self.key = viewControllerKey
    }

    func onViewDidDisappear(viewControllerKey: String) {
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
