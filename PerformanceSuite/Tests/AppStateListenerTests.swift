//
//  AppStateListenerTests.swift
//  PerformanceSuite-Tests
//
//  Created by Gleb Tarasov on 12/07/2021.
//

import UIKit
import XCTest

@testable import PerformanceSuite

class AppStateListenerTests: XCTestCase {

    func testResignActiveWorks() throws {
        let observer = DefaultAppStateListener()
        XCTAssertFalse(observer.wasInBackground)
        XCTAssertFalse(observer.isInBackground)
        NotificationCenter.default.post(name: UIApplication.willResignActiveNotification, object: nil)
        XCTAssertTrue(observer.wasInBackground)
        XCTAssertTrue(observer.isInBackground)
    }

    func testBecomeActiveWorks() throws {
        let observer = DefaultAppStateListener()
        XCTAssertFalse(observer.wasInBackground)
        XCTAssertFalse(observer.isInBackground)
        NotificationCenter.default.post(name: UIApplication.willResignActiveNotification, object: nil)
        XCTAssertTrue(observer.wasInBackground)
        XCTAssertTrue(observer.isInBackground)
        NotificationCenter.default.post(name: UIApplication.didBecomeActiveNotification, object: nil)
        XCTAssertTrue(observer.wasInBackground)
        XCTAssertFalse(observer.isInBackground)
    }

    func testWillResignActiveIsCalledSynchronouslyOnResignActiveAndTerminate() throws {
        let observer = DefaultAppStateListener()
        var calls = 0
        observer.willResignActive = { calls += 1 }
        NotificationCenter.default.post(name: UIApplication.willResignActiveNotification, object: nil)
        XCTAssertEqual(calls, 1)
        NotificationCenter.default.post(name: UIApplication.willTerminateNotification, object: nil)
        XCTAssertEqual(calls, 2)
    }
}
