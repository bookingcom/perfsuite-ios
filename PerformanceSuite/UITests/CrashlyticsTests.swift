//
//  CrashlyticsTests.swift
//  PerformanceSuite-UI-UITests
//
//  UI tests for the real Firebase Crashlytics integration (`enableWithCrashlyticsSupport`),
//  booted via the `CRASHLYTICS` launch argument.
//
//  Invariants under test:
//   - A real crash IS reported as `.crash` on the next launch
//     (`didCrashDuringPreviousExecution()` is true), foreground or background.
//   - A foreground hang is reported as the hang it is (`.fatalHang` / `.nonFatalHang`, in either
//     reporting mode) and NEVER as a crash on the next launch. Recording the on-demand hang report
//     writes Firebase's `previously-crashed` marker; if it is not cleared the next launch would
//     report a phantom `.crash`.
//   - A hang that happens entirely in the background is intentionally NOT detected (it is not a
//     user-visible hang), so it is reported as neither a hang nor a crash.
//

import XCTest

final class CrashlyticsTests: BaseTests {

    // MARK: - Real crash: must be reported as a crash on the next launch

    func testCrash_Foreground_IsReportedAsCrash() {
        launchClean(inBackground: false)
        triggerAndBackground("Crash", inBackground: false)
        waitForTimeout(2)  // crash happens
        relaunch()
        waitForMessage { $0 == .crash }
        assertHasMessages(.crash)
    }

    func testCrash_Background_IsReportedAsCrash() {
        launchClean(inBackground: true)
        triggerAndBackground("Crash", inBackground: true)
        waitForTimeout(6)  // delayed crash happens while backgrounded
        relaunch()
        waitForMessage { $0 == .crash }
        assertHasMessages(.crash)
    }

    // MARK: - Fatal hang: reported as a fatal hang, never as a crash (both reporting modes)

    func testFatalHang_Foreground_FatalHangsAsCrashes() {
        runFatalHang(hangsAsNonFatals: false)
        waitForMessage { $0 == .fatalHang }
        assertHasMessages(.fatalHang)
        assertNoMessages(.crash)
    }

    func testFatalHang_Foreground_FatalHangsAsNonFatals() {
        runFatalHang(hangsAsNonFatals: true)
        waitForMessage { $0 == .fatalHang }
        assertHasMessages(.fatalHang)
        assertNoMessages(.crash)
    }

    // A fatal hang that happens entirely in the background is not detected as a hang (it surfaces,
    // if at all, as a background watchdog termination); either way it must not be reported as a crash.
    func testFatalHang_Background_FatalHangsAsCrashes() {
        runBackgroundHang(menuItem: "Fatal hang", hangsAsNonFatals: false)
        assertNoMessages(.fatalHang)
        assertNoMessages(.crash)
    }

    func testFatalHang_Background_FatalHangsAsNonFatals() {
        runBackgroundHang(menuItem: "Fatal hang", hangsAsNonFatals: true)
        assertNoMessages(.fatalHang)
        assertNoMessages(.crash)
    }

    // MARK: - Recovered non-fatal hang: reported as non-fatal, never as a crash (both modes)

    func testNonFatalHang_Foreground_FatalHangsAsCrashes() {
        runRecoveredNonFatalHang(hangsAsNonFatals: false)
        waitForMessage { $0 == .nonFatalHang }
        assertHasMessages(.nonFatalHang)
        assertNoMessages(.crash)
    }

    func testNonFatalHang_Foreground_FatalHangsAsNonFatals() {
        runRecoveredNonFatalHang(hangsAsNonFatals: true)
        waitForMessage { $0 == .nonFatalHang }
        assertHasMessages(.nonFatalHang)
        assertNoMessages(.crash)
    }

    // A hang that happens entirely in the background is intentionally NOT detected by
    // PerformanceSuite (it is not a user-visible hang), so it is reported neither as a hang nor as
    // a crash.
    func testNonFatalHang_Background_FatalHangsAsCrashes() {
        runBackgroundHang(menuItem: "Non-fatal hang", hangsAsNonFatals: false)
        assertNoMessages(.nonFatalHang)
        assertNoMessages(.crash)
    }

    func testNonFatalHang_Background_FatalHangsAsNonFatals() {
        runBackgroundHang(menuItem: "Non-fatal hang", hangsAsNonFatals: true)
        assertNoMessages(.nonFatalHang)
        assertNoMessages(.crash)
    }

    // MARK: - Helpers

    private func env(clearStorage: Bool, inBackground: Bool, hangsAsNonFatals: Bool) -> [String: String] {
        var env = [inTestsKey: "1", crashlyticsKey: "1"]
        if clearStorage { env[clearStorageKey] = "1" }
        if hangsAsNonFatals { env[crashlyticsHangsAsNonFatalsKey] = "1" }
        // When backgrounding, delay the simulated issue so it happens after we go to the background.
        if inBackground { env[actionDelayKey] = "3" }
        return env
    }

    private func launchClean(inBackground: Bool, hangsAsNonFatals: Bool = false) {
        app.launchEnvironment = env(clearStorage: true, inBackground: inBackground, hangsAsNonFatals: hangsAsNonFatals)
        app.launch()
    }

    private func triggerAndBackground(_ menuItem: String, inBackground: Bool) {
        app.staticTexts[menuItem].tap()
        if inBackground {
            // The action is delayed (ACTION_DELAY); background now so it happens while backgrounded.
            XCUIDevice.shared.press(.home)
        }
    }

    /// Relaunch in Crashlytics mode (no storage clear) so we can observe what the previous run left
    /// behind - in particular whether Crashlytics thinks the app crashed.
    private func relaunch(hangsAsNonFatals: Bool = false) {
        app.launchEnvironment = env(clearStorage: false, inBackground: false, hangsAsNonFatals: hangsAsNonFatals)
        app.launch()
        waitForTimeout(3)
    }

    /// Foreground fatal hang: detected (`reportHangStarted` records it per the reporting mode), the
    /// app never recovers, so we kill it and relaunch.
    private func runFatalHang(hangsAsNonFatals: Bool) {
        app.launchEnvironment = env(clearStorage: true, inBackground: false, hangsAsNonFatals: hangsAsNonFatals)
        app.launch()
        app.staticTexts["Fatal hang"].tap()
        // Wait until the hang is actually detected before killing the app - a fixed sleep is racy on
        // slow CI runners (kill too early -> no fatal hang recorded -> the relaunch assertion times out).
        waitForMessage { $0 == .hangStarted }
        app.terminate()  // simulate the system killing the stuck app
        relaunch(hangsAsNonFatals: hangsAsNonFatals)
    }

    /// Foreground non-fatal hang: detected, then recovers (this is the path that records and then
    /// clears the on-demand report/marker).
    private func runRecoveredNonFatalHang(hangsAsNonFatals: Bool) {
        app.launchEnvironment = env(clearStorage: true, inBackground: false, hangsAsNonFatals: hangsAsNonFatals)
        app.launch()
        app.staticTexts["Non-fatal hang"].tap()
        // Wait until the recovered hang has actually been reported before killing the app - a fixed
        // sleep is racy on slow CI runners (kill before the report is captured -> the relaunch
        // assertion times out).
        waitForMessage { $0 == .nonFatalHang }
        app.terminate()
        relaunch(hangsAsNonFatals: hangsAsNonFatals)
    }

    /// Hang entirely in the background: the action is delayed, we go to the background first, and
    /// the hang happens there. PerformanceSuite intentionally does not detect background hangs, so
    /// nothing should be reported (and certainly not a crash on the next launch).
    private func runBackgroundHang(menuItem: String, hangsAsNonFatals: Bool) {
        app.launchEnvironment = env(clearStorage: true, inBackground: true, hangsAsNonFatals: hangsAsNonFatals)
        app.launch()
        app.staticTexts[menuItem].tap()
        XCUIDevice.shared.press(.home)  // background before the delayed hang fires
        waitForTimeout(12)              // hang occurs (and, if non-fatal, recovers) while backgrounded
        app.terminate()
        relaunch(hangsAsNonFatals: hangsAsNonFatals)
    }
}
