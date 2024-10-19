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
}
