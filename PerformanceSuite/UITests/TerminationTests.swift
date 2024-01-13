//
//  TerminationTests.swift
//  PerformanceAppUITests
//
//  Created by Gleb Tarasov on 18/12/2023.
//

import XCTest


/// **NB!**: Termination observers do not start in DEBUG by default.
/// These tests will work only in Release.
/// You can run those tests from `UITests` scheme for that.
final class TerminationTests: XCTestCase {

    private var client: UITestsInterop.Client!
    private let app = XCUIApplication()

    override func setUp() {
        super.setUp()
        client = UITestsInterop.Client()
    }
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

        assertHasMessages(.watchdogTermination)
        assertNoMessages(.hangStarted, .nonFatalHang, .fatalHang, .crash)
    }

    func testFatalHang() throws {
        performFirstLaunch()

        XCTAssertFalse(client.messages.contains { $0 == .hangStarted })
        XCTAssertFalse(client.messages.contains { $0 == .fatalHang })

        app.staticTexts["Fatal hang"].tap()
        waitForTimeout(5)

        // app won't die by itself, relaunch the app
        app.terminate()
        app.launch()

        waitForMessage { $0 == .fatalHang }

        assertHasMessages(.hangStarted, .fatalHang)
        assertNoMessages(.crash, .nonFatalHang, .watchdogTermination)
    }

    func testNonFatalHang() throws {
        performFirstLaunch()
        XCTAssertFalse(client.messages.contains { $0 == .hangStarted })
        XCTAssertFalse(client.messages.contains { $0 == .nonFatalHang })
        app.staticTexts["Non-fatal hang"].tap()
        waitForTimeout(4)
        waitForMessage { $0 == .nonFatalHang }

        assertHasMessages(.hangStarted, .nonFatalHang)
        assertNoMessages(.crash, .fatalHang, .watchdogTermination)
    }

    func testCrash() throws {
        performFirstLaunch()
        XCTAssertFalse(client.messages.contains { $0 == .crash })
        app.staticTexts["Crash"].tap()
        waitForTimeout(1)
        app.launch()
        waitForMessage { $0 == .crash }

        assertNoMessages(.hangStarted, .nonFatalHang, .fatalHang, .watchdogTermination)
    }

    private func assertNoMessages(file: StaticString = #file, line: UInt = #line, _ messages: Message...) {
        for m in messages {
            XCTAssertFalse(client.messages.contains { $0 == m }, file: file, line: line)
        }
    }

    private func assertHasMessages(file: StaticString = #file, line: UInt = #line, _ messages: Message...) {
        for m in messages {
            XCTAssertTrue(client.messages.contains { $0 == m }, file: file, line: line)
        }
    }

    private func performFirstLaunch() {
        app.launchEnvironment = [inTestsKey: "1", clearStorageKey: "1"]
        app.launch()
        app.launchEnvironment = [inTestsKey: "1"]
    }

    private func waitForMessage(_ checker: @escaping (Message) -> Bool) {
        let exp = expectation(description: "wait for message")
        var fired = false
        waitingTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self = self, !fired else { return }
            if self.client.messages.contains(where: checker) {
                exp.fulfill()
                fired = true
            }
        }

        wait(for: [exp], timeout: 10)
    }
    private var waitingTimer: Timer?

    private func waitForTimeout(_ seconds: Int) {
        let exp = expectation(description: "wait for timeout")
        DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(seconds)) {
            exp.fulfill()
        }
        wait(for: [exp], timeout: Double(seconds + 1))
    }
}
