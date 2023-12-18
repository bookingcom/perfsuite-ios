//
//  TerminationTests.swift
//  PerformanceAppUITests
//
//  Created by Gleb Tarasov on 18/12/2023.
//

import XCTest

final class TerminationTests: XCTestCase {

    func testNonFatalHang() throws {
        // UI tests must launch the application that they test.
        let app = XCUIApplication()
        app.launch()

        app.staticTexts["Non-fatal hang"].tap()
    }
}
