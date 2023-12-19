//
//  TerminationTests.swift
//  PerformanceAppUITests
//
//  Created by Gleb Tarasov on 18/12/2023.
//

import XCTest

final class TerminationTests: XCTestCase {

    let client = UITestsInterop.Client()

    func testNonFatalHang() throws {
        // UI tests must launch the application that they test.
        let app = XCUIApplication()
        app.launch()

        app.staticTexts["Watchdog termination"].tap()

        app.launch()

        Thread.sleep(forTimeInterval: 100000)

        XCTAssert(client.messages.contains(where: { m in
            m == .watchdogTermination
        }))
    }
}
