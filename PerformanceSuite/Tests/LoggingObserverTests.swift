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
