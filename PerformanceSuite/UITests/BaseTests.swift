//
//  BaseTests.swift
//  PerformanceSuite-UI-UITests
//
//  Created by Gleb Tarasov on 13/01/2024.
//

import XCTest

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
    func waitForCondition(timeout: TimeInterval = 180, _ check: @escaping () -> Bool) {
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
