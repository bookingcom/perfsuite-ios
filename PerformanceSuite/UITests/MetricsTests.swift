//
//  MetricsTests.swift
//  PerformanceSuite-UI-UITests
//
//  Created by Gleb Tarasov on 13/01/2024.
//

import XCTest

class MetricsTests: BaseTests {
    func testTTI() throws {
        performFirstLaunch()
        let ttiMessage = Message.tti(duration: 0, screen: "list")
        assertNoMessages(ttiMessage)

        app.staticTexts["TTI"].tap()
        waitForMessage { $0 == ttiMessage }

        let foundMessage = try XCTUnwrap(client.messages.first(where: { $0 == ttiMessage }))
        if case .tti(let duration, _) = foundMessage {
            XCTAssertGreaterThan(duration, 500)
        }
    }

    func testFreezeTime() throws {
        performFirstLaunch()
        let ftMessage = Message.freezeTime(duration: 0, screen: "list")
        assertNoMessages(ftMessage)

        app.staticTexts["Freeze Time"].tap()
        waitForMessage { $0 == ftMessage }

        let foundMessage = try XCTUnwrap(client.messages.first(where: { $0 == ftMessage }))
        if case .tti(let duration, _) = foundMessage {
            XCTAssertGreaterThan(duration, 60)
        }
    }
}
