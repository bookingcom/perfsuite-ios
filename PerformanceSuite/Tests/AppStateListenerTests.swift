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

    // fixFatalHangOnResignActive: variant test; keep on cleanup, without the experiment setup.
    func testWillChangeIsCalledSynchronouslyBeforeTheStateChanges() throws {
        PerformanceMonitoring.experiments = Experiments(fixFatalHangOnResignActive: true)
        defer {
            PerformanceMonitoring.experiments = Experiments()
        }
        let observer = DefaultAppStateListener()
        var states: [Bool] = []
        observer.willChange = { states.append(observer.isInBackground) }
        // Becoming active while not in background (like after launch) isn't a change.
        NotificationCenter.default.post(name: UIApplication.didBecomeActiveNotification, object: nil)
        XCTAssertEqual(states, [])
        NotificationCenter.default.post(name: UIApplication.willResignActiveNotification, object: nil)
        XCTAssertEqual(states, [false])
        XCTAssertTrue(observer.isInBackground)
        NotificationCenter.default.post(name: UIApplication.didBecomeActiveNotification, object: nil)
        XCTAssertEqual(states, [false, true])
        XCTAssertFalse(observer.isInBackground)
    }
}
