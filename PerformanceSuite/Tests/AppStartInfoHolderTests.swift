//
//  AppStartInfoHolderTests.swift
//  PerformanceSuite-Tests
//
//  Created by Gleb Tarasov on 19/12/2022.
//

import XCTest

@testable import PerformanceSuite

final class AppStartInfoHolderTests: XCTestCase {

    override func setUp() {
        super.setUp()
        AppInfoHolder.resetForTests()
    }

    func testPrewarmingDetection() {
        XCTAssertFalse(AppInfoHolder.appStartInfo.appStartedWithPrewarming)
        AppInfoHolder.recordMainStarted()
        XCTAssertFalse(AppInfoHolder.appStartInfo.appStartedWithPrewarming)

        setenv("ActivePrewarm", "0", 1)

        AppInfoHolder.recordMainStarted()
        XCTAssertFalse(AppInfoHolder.appStartInfo.appStartedWithPrewarming)

        setenv("ActivePrewarm", "1", 1)
        AppInfoHolder.recordMainStarted()
        XCTAssertTrue(AppInfoHolder.appStartInfo.appStartedWithPrewarming)

        setenv("ActivePrewarm", "", 1)
    }

    func testRuntimeInfo() {
        XCTAssertEqual(AppInfoHolder.appRuntimeInfo.openedScreens, [])
        AppInfoHolder.screenOpened("screen1")
        XCTAssertEqual(AppInfoHolder.appRuntimeInfo.openedScreens, ["screen1"])

        AppInfoHolder.screenOpened("screen2")
        AppInfoHolder.screenOpened("screen3")
        XCTAssertEqual(AppInfoHolder.appRuntimeInfo.openedScreens, ["screen1", "screen2", "screen3"])
    }
}
