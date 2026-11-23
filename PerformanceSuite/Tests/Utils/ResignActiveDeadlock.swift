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
        let consumerStarted = expectation(description: "consumerQueue item started")
        let consumerDone = expectation(description: "consumerQueue item finished")
        let mainWorkDone = DispatchSemaphore(value: 0)
        var mainWorkTimedOut = false

        // Same QoS as main, so main waiting for this item isn't reported as a priority inversion.
        PerformanceMonitoring.consumerQueue.async(qos: .userInteractive, flags: .enforceQoS) {
            consumerStarted.fulfill()
            mainWorkTimedOut = mainWorkDone.wait(timeout: .now() + 2) == .timedOut
            consumerDone.fulfill()
        }
        wait(for: [consumerStarted], timeout: 5)

        // Main work the consumer item waits for, which main can only run after the current turn.
        DispatchQueue.main.async {
            mainWorkDone.signal()
        }
        NotificationCenter.default.post(name: UIApplication.willResignActiveNotification, object: nil)

        wait(for: [consumerDone], timeout: 5)
        XCTAssertFalse(mainWorkTimedOut, "willResignActive deadlocked waiting for consumerQueue", file: file, line: line)

        drainQueuesAfterMainTurn()
    }

    /// Lets the deliveries queued so far run: those queued on main after the current turn first, then on
    /// `PerformanceMonitoring.queue` and `consumerQueue`. Waiting with expectations rather than `sync`, which
    /// from main would be reported as waiting on a lower-QoS thread.
    func drainQueuesAfterMainTurn() {
        for queue in [DispatchQueue.main, PerformanceMonitoring.queue, PerformanceMonitoring.consumerQueue] {
            let drained = expectation(description: "\(queue.label) drained")
            queue.async(qos: .userInteractive, flags: .enforceQoS) {
                drained.fulfill()
            }
            wait(for: [drained], timeout: 5)
        }
    }
}
