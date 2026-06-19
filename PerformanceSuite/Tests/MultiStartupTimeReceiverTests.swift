//
//  MultiStartupTimeReceiverTests.swift
//  PerformanceSuite-Tests
//
//  Created by Ahmed Nafei on 30/04/2026.
//

import XCTest
@testable import PerformanceSuite

final class MultiStartupTimeReceiverTests: XCTestCase {

    private final class StartupStub: StartupTimeReceiver {
        var received: [StartupTimeData] = []
        func startupTimeReceived(_ data: StartupTimeData) {
            received.append(data)
        }
    }

    private func makeData(prewarmed: Bool = false) -> StartupTimeData {
        StartupTimeData(
            totalTime: .milliseconds(1500),
            preMainTime: .milliseconds(300),
            mainTime: .milliseconds(1200),
            totalBeforeViewControllerTime: .milliseconds(900),
            mainBeforeViewControllerTime: .milliseconds(600),
            appStartInfo: AppStartInfo(appStartedWithPrewarming: prewarmed)
        )
    }

    func testFanOutToAllReceivers() {
        let first = StartupStub()
        let second = StartupStub()
        let multi = MultiStartupTimeReceiver(receivers: [first, second])

        let data = makeData()
        multi.startupTimeReceived(data)

        XCTAssertEqual(first.received.count, 1)
        XCTAssertEqual(second.received.count, 1)
        XCTAssertEqual(first.received.first?.totalTime, data.totalTime)
        XCTAssertEqual(second.received.first?.totalTime, data.totalTime)
    }

    func testPrewarmFlagPropagated() {
        let stub = StartupStub()
        let multi = MultiStartupTimeReceiver(receivers: [stub])

        multi.startupTimeReceived(makeData(prewarmed: true))

        XCTAssertEqual(stub.received.count, 1)
        XCTAssertTrue(stub.received.first?.appStartInfo.appStartedWithPrewarming == true)
    }

    func testEmptyReceiversArrayDoesNotCrash() {
        let multi = MultiStartupTimeReceiver(receivers: [])
        multi.startupTimeReceived(makeData())
    }

    func testOrderPreserved() {
        var order: [Int] = []
        final class OrderingStub: StartupTimeReceiver {
            let id: Int
            let onCall: (Int) -> Void
            init(id: Int, onCall: @escaping (Int) -> Void) {
                self.id = id
                self.onCall = onCall
            }
            func startupTimeReceived(_ data: StartupTimeData) {
                onCall(id)
            }
        }
        let multi = MultiStartupTimeReceiver(receivers: [
            OrderingStub(id: 10, onCall: { order.append($0) }),
            OrderingStub(id: 11, onCall: { order.append($0) }),
            OrderingStub(id: 12, onCall: { order.append($0) }),
        ])
        multi.startupTimeReceived(makeData())

        XCTAssertEqual(order, [10, 11, 12])
    }

    // MARK: - Live-measurement dispatch (single live child)

    func testSingleLiveChildDrivesMeasurementAndRoundTripsHandle() {
        let live = LiveStartupReceiverStub()
        let legacy = StartupStub()
        let multi = MultiStartupTimeReceiver(receivers: [live, legacy])

        let context = multi.startupMeasurementStarted()
        XCTAssertNotNil(context)
        multi.startupMeasurementEnded(makeData(), context: context)

        XCTAssertEqual(live.startedCount, 1)
        XCTAssertEqual(live.endedContexts.count, 1)
        XCTAssertNotNil(live.endedContexts.first ?? nil)
        XCTAssertEqual(legacy.received.count, 1, "Non-live child gets the completed callback")
    }
}

// File-scope so the nested `Ctx` handle stays at one level of nesting (SwiftLint `nesting`).
private final class LiveStartupReceiverStub: LiveStartupTimeReceiver {
    final class Ctx: MeasurementHandle {
        func cancel() {}
    }
    var startedCount = 0
    var endedContexts: [(any MeasurementHandle)?] = []
    func startupTimeReceived(_ data: StartupTimeData) {}
    func startupMeasurementStarted() -> (any MeasurementHandle)? {
        startedCount += 1
        return Ctx()
    }
    func startupMeasurementEnded(_ data: StartupTimeData, context: (any MeasurementHandle)?) {
        endedContexts.append(context)
    }
}
