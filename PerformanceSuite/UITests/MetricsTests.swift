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

    func testFragmentTTI() throws {
        performFirstLaunch()
        let fragment1 = Message.fragmentTTI(duration: 0, fragment: "fragment1")
        let fragment2 = Message.fragmentTTI(duration: 0, fragment: "fragment2")
        let fragment3 = Message.fragmentTTI(duration: 0, fragment: "fragment3")
        assertNoMessages(fragment1, fragment2, fragment3)

        app.staticTexts["Fragment TTI"].tap()
        waitForMessage { $0 == fragment1 }


        func assertDuration(fragment: Message, duration: Int) throws {
            let foundMessage = try XCTUnwrap(client.messages.first(where: { $0 == fragment }))
            if case .fragmentTTI(let duration, _) = foundMessage {
                XCTAssertEqual(duration, duration, accuracy: 10)
            }
        }

        try assertDuration(fragment: fragment1, duration: 300)
        try assertDuration(fragment: fragment2, duration: 50)
        try assertDuration(fragment: fragment3, duration: 100)
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

    func testStartupTime() throws {
        performFirstLaunch()
        let startupMessage = Message.startupTime(duration: 0)
        waitForMessage { $0 == startupMessage }

        let foundMessage = try XCTUnwrap(client.messages.first(where: { $0 == startupMessage }))
        if case .startupTime(let duration) = foundMessage {
            XCTAssertGreaterThan(duration, 2000)
        }
    }

    func testAppFreezeTime() throws {
        performFirstLaunch()
        let aftMessage = Message.appFreezeTime(duration: 0)
        assertNoMessages(aftMessage)

        app.staticTexts["Freeze Time"].tap()
        waitForMessage { $0 == aftMessage }

        let foundMessage = try XCTUnwrap(client.messages.first(where: { $0 == aftMessage }))
        if case .appFreezeTime(let duration) = foundMessage {
            XCTAssertGreaterThan(duration, 2000)
        }
    }
}
