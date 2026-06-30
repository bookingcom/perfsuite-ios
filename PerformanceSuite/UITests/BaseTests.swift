//
//  BaseTests.swift
//  PerformanceSuite-UI-UITests
//
//  Created by Gleb Tarasov on 13/01/2024.
//

import XCTest

/// Default timeout for event-driven waits (`waitForCondition` / `waitForMessage`). See the
/// rationale on `waitForCondition`.
private let uiTestDefaultWaitTimeout: TimeInterval = 45

class BaseTests: XCTestCase {
    var client: UITestsInterop.Client!
    let app = XCUIApplication()
    private var waitingTimer: Timer?

    override func setUp() {
        super.setUp()
        client = UITestsInterop.Client()
    }

    override func tearDown() {
        super.tearDown()
        waitingTimer?.invalidate()
        client.reset()
    }

    func waitForTimeout(_ seconds: Int) {
        let exp = expectation(description: "wait for timeout")
        DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(seconds)) {
            exp.fulfill()
        }
        wait(for: [exp], timeout: Double(seconds + 1))
    }

    func assertNoMessages(file: StaticString = #file, line: UInt = #line, _ messages: Message...) {
        for m in messages {
            XCTAssertFalse(client.messages.contains { $0 == m }, file: file, line: line)
        }
    }

    func assertHasMessages(file: StaticString = #file, line: UInt = #line, _ messages: Message...) {
        for m in messages {
            XCTAssertTrue(client.messages.contains { $0 == m }, file: file, line: line)
        }
    }

    func performFirstLaunch() {
        app.launchEnvironment = [inTestsKey: "1", clearStorageKey: "1"]
        app.launch()
        app.launchEnvironment = [inTestsKey: "1"]
    }

    func waitForMessage(_ checker: @escaping (Message) -> Bool) {
        waitForCondition { [weak self] in
            self?.client.messages.contains(where: checker) ?? false
        }
    }

    /// Polls `check` every 0.1s up to the timeout, fulfilling when it returns
    /// true. Useful when the success condition is a function of all received
    /// messages (e.g. an accumulated total) rather than the presence of a
    /// single message.
    ///
    /// The default timeout is deliberately tight: a message that is going to arrive shows up within
    /// a few seconds once its trigger fires, so a long timeout only inflates the cost of a *failing*
    /// (often flaky) wait. 45s leaves ample margin for a slow CI relaunch while making a failed
    /// attempt ~4x cheaper than the old 180s — which, multiplied by retries, used to blow the CI
    /// 30-minute cap.
    func waitForCondition(timeout: TimeInterval = uiTestDefaultWaitTimeout, _ check: @escaping () -> Bool) {
        let exp = expectation(description: "wait for condition")
        var fired = false
        waitingTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
            guard !fired else { return }
            if check() {
                exp.fulfill()
                fired = true
            }
        }

        wait(for: [exp], timeout: timeout)
    }
}
