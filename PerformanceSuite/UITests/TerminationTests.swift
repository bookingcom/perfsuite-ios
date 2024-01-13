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
final class TerminationTests: BaseTests {

    func testWatchdogTermination() throws {
        performFirstLaunch()
        assertNoMessages(.watchdogTermination)

        app.staticTexts["Watchdog termination"].tap()
        app.launch()
        waitForMessage { $0 == .watchdogTermination }

        assertHasMessages(.watchdogTermination)
        assertNoMessages(.hangStarted, .nonFatalHang, .fatalHang, .crash)
    }

    func testFatalHang() throws {
        performFirstLaunch()
        assertNoMessages(.hangStarted, .fatalHang)

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
        assertNoMessages(.hangStarted, .nonFatalHang)
        app.staticTexts["Non-fatal hang"].tap()
        waitForTimeout(4)
        waitForMessage { $0 == .nonFatalHang }

        assertHasMessages(.hangStarted, .nonFatalHang)
        assertNoMessages(.crash, .fatalHang, .watchdogTermination)
    }

    func testCrash() throws {
        performFirstLaunch()
        assertNoMessages(.crash)
        app.staticTexts["Crash"].tap()
        waitForTimeout(1)
        app.launch()
        waitForMessage { $0 == .crash }

        assertNoMessages(.hangStarted, .nonFatalHang, .fatalHang, .watchdogTermination)
    }
}
