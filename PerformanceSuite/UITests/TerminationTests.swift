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

        waitForMessage { $0 == .hangStarted }

        // app won't die by itself, relaunch the app
        app.terminate()
        app.launch()

        waitForMessage { $0 == .fatalHang }
        assertNoMessages(.crash, .nonFatalHang, .watchdogTermination)
    }

    func testNonFatalHang() throws {
        performFirstLaunch()
        assertNoMessages(.hangStarted, .nonFatalHang)
        app.staticTexts["Non-fatal hang"].tap()
        waitForTimeout(5)
        waitForMessage { $0 == .nonFatalHang }

        assertHasMessages(.hangStarted, .nonFatalHang)
        assertNoMessages(.crash, .fatalHang, .watchdogTermination)
    }

    func testCrash() throws {
        performFirstLaunch()

#if swift(>=5.9)
        let message = Message.crash // For Xcode 15 or later it should work fine
        let noMessage = Message.watchdogTermination
#else
        let message = Message.watchdogTermination // In earlier versions our crash handling doesn't work somehow, so we track crashes as watchdog terminations
        let noMessage = Message.crash
#endif

        assertNoMessages(message)
        app.staticTexts["Crash"].tap()
        waitForTimeout(1)
        app.launch()
        waitForMessage { $0 == message }

        assertNoMessages(.hangStarted, .nonFatalHang, .fatalHang, noMessage)
    }

    func testMemoryLeak() throws {
        performFirstLaunch()
        assertNoMessages(.memoryLeak)
        app.staticTexts["Memory Leak"].tap()
        waitForMessage { $0 == .memoryLeak }
    }

    func testStartupFatalHang() throws {
        // First launch: clear storage
        performFirstLaunch()
        assertNoMessages(.fatalHang, .startupFatalHang, .hangStarted)

        // Second launch: trigger startup fatal hang
        app.terminate()
        app.launchEnvironment = [inTestsKey: "1", startupFatalHangKey: "1"]
        app.launch()

        // Wait for hang to be detected (hang detection takes time)
        waitForTimeout(5)

        // Kill the app during the hang (simulating system kill or user force quit)
        // Note: We may or may not receive hangStarted before termination, so we don't check for it
        app.terminate()

        // Third launch: should receive startup fatal hang callback (duringStartup=true)
        app.launchEnvironment = [inTestsKey: "1"]
        app.launch()

        waitForMessage { $0 == .startupFatalHang }
        // The startup fatal hang was successfully detected and reported!
        assertNoMessages(.crash, .nonFatalHang, .fatalHang)
        // Note: watchdogTermination might also be reported, which is acceptable
    }
}
