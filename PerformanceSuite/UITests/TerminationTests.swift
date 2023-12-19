//
//  TerminationTests.swift
//  PerformanceAppUITests
//
//  Created by Gleb Tarasov on 18/12/2023.
//

import XCTest

final class TerminationTests: XCTestCase {

    private let client = UITestsInterop.Client()
    private let app = XCUIApplication()

    override func tearDown() {
        super.tearDown()
        waitingTimer?.invalidate()
        client.reset()
    }

    func testWatchdogTermination() throws {
        performFirstLaunch()

        XCTAssertFalse(client.messages.contains { $0 == .watchdogTermination })

        app.staticTexts["Watchdog termination"].tap()
        app.launch()
        waitForMessage { $0 == .watchdogTermination }
    }

    func testFatalHang() throws {
        performFirstLaunch()

        XCTAssertFalse(client.messages.contains { $0 == .fatalHang })

        app.staticTexts["Fatal hang"].tap()
        waitForTimeout(3)

        // app won't die by itself, relaunch the app
        app.terminate()
        app.launch()

        waitForMessage { $0 == .fatalHang }
    }

    func testNonFatalHang() throws {
        performFirstLaunch()
        XCTAssertFalse(client.messages.contains { $0 == .nonFatalHang })
        app.staticTexts["Non-fatal hang"].tap()
        waitForTimeout(3)
        waitForMessage { $0 == .nonFatalHang }
    }

    private func performFirstLaunch() {
        app.launchEnvironment = [inTestsKey: "1", clearStorageKey: "1"]
        app.launch()
        app.launchEnvironment = [inTestsKey: "1"]
    }

    private func waitForMessage(_ checker: @escaping (Message) -> Bool) {
        let exp = expectation(description: "wait for message")
        waitingTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            if self.client.messages.contains(where: checker) {
                exp.fulfill()
            }
        }

        wait(for: [exp], timeout: 10)
    }
    private var waitingTimer: Timer?

    private func waitForTimeout(_ timeout: TimeInterval) {
        let exp = expectation(description: "wait for timeout")
        DispatchQueue.main.asyncAfter(deadline: .now() + timeout) {
            exp.fulfill()
        }
        wait(for: [exp], timeout: timeout + 1)
    }
}
