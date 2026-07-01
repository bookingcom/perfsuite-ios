//
//  StartupTests.swift
//  PerformanceSuite-UI-UITests
//
//  UI tests for startup-time reporting around app backgrounding.
//
//  Scenario under test: the app is launched, sent to the background before startup finishes (before
//  the first `viewDidAppear`), then brought back to the foreground. The measured startup time would
//  otherwise include the background time and be misleadingly long, so with the
//  `dropStartupTimeWhenAppWasInBackground` experiment enabled PerformanceSuite drops the event.
//

import XCTest

final class StartupTests: BaseTests {

    /// Backgrounding during startup must suppress the startup-time event (experiment enabled).
    ///
    /// The app boots with `STARTUP_BACKGROUND`, which (a) enables the experiment and (b) defers the
    /// whole UI setup by a few seconds, giving us a deterministic window to background and
    /// foreground the app before the first `viewDidAppear`.
    func testStartupTime_BackgroundedDuringStartup_IsDropped() {
        app.launchEnvironment = [inTestsKey: "1", clearStorageKey: "1", startupBackgroundKey: "1"]
        app.launch()

        // Background before startup finishes (the UI is still deferred at this point), then return.
        XCUIDevice.shared.press(.home)
        waitForTimeout(2)
        app.activate()

        // The app DID finish starting — the menu UI eventually appears...
        XCTAssertTrue(
            app.staticTexts["Fatal hang"].waitForExistence(timeout: 20),
            "App never finished launching, so the test can't distinguish 'dropped' from 'never started'")

        // ...but the startup-time event must NOT be reported, because startup spanned a backgrounding.
        waitForTimeout(3)  // give a would-be startup event time to arrive
        assertNoMessages(.startupTime(duration: 0))
    }
}
