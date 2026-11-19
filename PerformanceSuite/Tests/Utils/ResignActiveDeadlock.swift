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

    /// Posts `willResignActive` on main while a `consumerQueue` item waits for main, the way a receiver
    /// posting to a `queue: .main` notification observer does. If the `willResignActive` handling waits for
    /// `consumerQueue` without a bound, main and `consumerQueue` wait for each other.
    ///
    /// The `consumerQueue` item gives up waiting after a timeout, which breaks the deadlock so the test fails
    /// instead of freezing the runner.
    func assertWillResignActiveDoesNotDeadlock(file: StaticString = #filePath, line: UInt = #line) {
        precondition(Thread.isMainThread)
        let consumerIsWaiting = DispatchSemaphore(value: 0)
        let mainWorkDone = DispatchSemaphore(value: 0)
        let consumerDone = expectation(description: "consumerQueue item finished")
        var mainWorkTimedOut = false

        PerformanceMonitoring.consumerQueue.async {
            DispatchQueue.main.async {
                mainWorkDone.signal()
            }
            consumerIsWaiting.signal()
            mainWorkTimedOut = mainWorkDone.wait(timeout: .now() + 2) == .timedOut
            consumerDone.fulfill()
        }
        consumerIsWaiting.wait()

        NotificationCenter.default.post(name: UIApplication.willResignActiveNotification, object: nil)

        wait(for: [consumerDone], timeout: 5)
        XCTAssertFalse(mainWorkTimedOut, "willResignActive deadlocked waiting for consumerQueue", file: file, line: line)
        PerformanceMonitoring.consumerQueue.sync {}
    }
}
