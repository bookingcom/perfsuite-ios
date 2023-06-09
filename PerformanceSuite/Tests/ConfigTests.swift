//
//  ConfigTests.swift
//  PerformanceSuite-Tests
//
//  Created by Gleb Tarasov on 28/01/2022.
//

import XCTest

@testable import PerformanceSuite

class ConfigTests: XCTestCase {

    func testSingleOptions() throws {
        let watchdogTerminationsStub = WatchdogTerminationsReceiverStub()
        var config: Config = [.watchdogTerminations(watchdogTerminationsStub)]
        XCTAssertNotNil(config.watchdogTerminationsReceiver)
        XCTAssert(config.watchdogTerminationsReceiver === watchdogTerminationsStub)
        XCTAssertNil(config.hangsReceiver)

        let hangsStub = HangsReceiverStub()
        config = [.hangs(hangsStub)]
        XCTAssertNil(config.watchdogTerminationsReceiver)
        XCTAssertNotNil(config.hangsReceiver)
        XCTAssert(config.hangsReceiver === hangsStub)
    }

    func testMultipleOptions() throws {
        let watchdogTerminationsStub = WatchdogTerminationsReceiverStub()
        let hangsStub = HangsReceiverStub()
        let renderingStub = RenderingMetricsReceiverStub()
        let appRenderingStub = AppRenderingMetricsReceiverStub()
        let ttiStub = TTIMetricsReceiverStub()

        var config: Config = [.watchdogTerminations(watchdogTerminationsStub), .hangs(hangsStub), .screenLevelTTI(ttiStub)]
        XCTAssert(config.watchdogTerminationsReceiver === watchdogTerminationsStub)
        XCTAssert(config.hangsReceiver === hangsStub)
        XCTAssert(config.screenTTIReceiver === ttiStub)
        XCTAssertNil(config.appRenderingReceiver)
        XCTAssertNil(config.screenRenderingReceiver)
        XCTAssertFalse(config.renderingEnabled)

        config = [.watchdogTerminations(watchdogTerminationsStub), .hangs(hangsStub), .screenLevelTTI(ttiStub), .screenLevelRendering(renderingStub)]
        XCTAssert(config.watchdogTerminationsReceiver === watchdogTerminationsStub)
        XCTAssert(config.hangsReceiver === hangsStub)
        XCTAssert(config.screenTTIReceiver === ttiStub)
        XCTAssertNil(config.appRenderingReceiver)
        XCTAssert(config.screenRenderingReceiver === renderingStub)
        XCTAssertTrue(config.renderingEnabled)

        config = [
            .watchdogTerminations(watchdogTerminationsStub), .hangs(hangsStub), .screenLevelTTI(ttiStub), .screenLevelRendering(renderingStub),
            .appLevelRendering(appRenderingStub),
        ]
        XCTAssert(config.watchdogTerminationsReceiver === watchdogTerminationsStub)
        XCTAssert(config.hangsReceiver === hangsStub)
        XCTAssert(config.screenTTIReceiver === ttiStub)
        XCTAssert(config.appRenderingReceiver === appRenderingStub)
        XCTAssert(config.screenRenderingReceiver === renderingStub)
        XCTAssertTrue(config.renderingEnabled)
    }
}
