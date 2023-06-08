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
        let oomStub = OutOfMemoryReceiverStub()
        var config: Config = [.outOfMemory(oomStub)]
        XCTAssertNotNil(config.oomReceiver)
        XCTAssert(config.oomReceiver === oomStub)
        XCTAssertNil(config.hangReceiver)

        let hangStub = HangReceiverStub()
        config = [.hangs(hangStub)]
        XCTAssertNil(config.oomReceiver)
        XCTAssertNotNil(config.hangReceiver)
        XCTAssert(config.hangReceiver === hangStub)
    }

    func testMultipleOptions() throws {
        let oomStub = OutOfMemoryReceiverStub()
        let hangStub = HangReceiverStub()
        let renderingStub = RenderingMetricsReceiverStub()
        let appRenderingStub = AppRenderingMetricsReceiverStub()
        let ttiStub = TTIMetricsReceiverStub()

        var config: Config = [.outOfMemory(oomStub), .hangs(hangStub), .screenLevelTTI(ttiStub)]
        XCTAssert(config.oomReceiver === oomStub)
        XCTAssert(config.hangReceiver === hangStub)
        XCTAssert(config.screenTTIReceiver === ttiStub)
        XCTAssertNil(config.appRenderingReceiver)
        XCTAssertNil(config.screenRenderingReceiver)
        XCTAssertFalse(config.renderingEnabled)

        config = [.outOfMemory(oomStub), .hangs(hangStub), .screenLevelTTI(ttiStub), .screenLevelRendering(renderingStub)]
        XCTAssert(config.oomReceiver === oomStub)
        XCTAssert(config.hangReceiver === hangStub)
        XCTAssert(config.screenTTIReceiver === ttiStub)
        XCTAssertNil(config.appRenderingReceiver)
        XCTAssert(config.screenRenderingReceiver === renderingStub)
        XCTAssertTrue(config.renderingEnabled)

        config = [
            .outOfMemory(oomStub), .hangs(hangStub), .screenLevelTTI(ttiStub), .screenLevelRendering(renderingStub),
            .appLevelRendering(appRenderingStub),
        ]
        XCTAssert(config.oomReceiver === oomStub)
        XCTAssert(config.hangReceiver === hangStub)
        XCTAssert(config.screenTTIReceiver === ttiStub)
        XCTAssert(config.appRenderingReceiver === appRenderingStub)
        XCTAssert(config.screenRenderingReceiver === renderingStub)
        XCTAssertTrue(config.renderingEnabled)
    }
}
