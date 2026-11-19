//
//  ResignActiveDeadlock.swift
//  PerformanceSuiteTests
//
//  Created by Gleb Tarasov on 19/11/2026.
//

import UIKit
import XCTest

@testable import PerformanceSuite

extension XCTestCase {

    /// Posts `willResignActive` while a `consumerQueue` item waits for the main thread, the way a receiver
    /// posting to a `queue: .main` notification observer does. If the `willResignActive` handling waits for
    /// `consumerQueue` without a bound, main and `consumerQueue` wait for each other forever.
    ///
    /// A serial queue stands in for the main thread, so a deadlock fails the test instead of freezing the
    /// runner. The cycle is broken afterwards, so later tests can still use `consumerQueue`.
    func assertWillResignActiveDoesNotDeadlock(file: StaticString = #filePath, line: UInt = #line) {
        let fakeMain = DispatchQueue(label: "fake_main_queue")
        // Tests usually run `PerformanceMonitoring.queue` on `.main`, which would move the blocking wait onto
        // the real main thread.
        let previousQueue = PerformanceMonitoring.changeQueueForTests(DispatchQueue(label: "test_monitoring_queue"))
        defer {
            PerformanceMonitoring.changeQueueForTests(previousQueue)
        }

        let consumerIsWaiting = DispatchSemaphore(value: 0)
        let mainWorkDone = DispatchSemaphore(value: 0)
        let resignHandled = expectation(description: "willResignActive handled")

        // Main is busy (e.g. starting an auth session) when the system deactivates the scene.
        fakeMain.async {
            consumerIsWaiting.wait()
            NotificationCenter.default.post(name: UIApplication.willResignActiveNotification, object: nil)
            resignHandled.fulfill()
        }
        // Queued for main behind the deactivation, and waited for synchronously.
        PerformanceMonitoring.consumerQueue.async {
            fakeMain.async {
                mainWorkDone.signal()
            }
            consumerIsWaiting.signal()
            mainWorkDone.wait()
        }

        let result = XCTWaiter().wait(for: [resignHandled], timeout: 2)
        XCTAssertEqual(result, .completed, "willResignActive deadlocked waiting for consumerQueue", file: file, line: line)

        mainWorkDone.signal()
        fakeMain.sync {}
        PerformanceMonitoring.consumerQueue.sync {}
    }
}
