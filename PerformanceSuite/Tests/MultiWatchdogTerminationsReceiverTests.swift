//
//  MultiWatchdogTerminationsReceiverTests.swift
//  PerformanceSuite-Tests
//
//  Created by Ahmed Nafei on 30/04/2026.
//

import UIKit
import XCTest
@testable import PerformanceSuite

final class MultiWatchdogTerminationsReceiverTests: XCTestCase {

    private final class WatchdogStub: WatchdogTerminationsReceiver {
        var received: [WatchdogTerminationData] = []
        func watchdogTerminationReceived(_ data: WatchdogTerminationData) {
            received.append(data)
        }
    }

    private func makeData() -> WatchdogTerminationData {
        WatchdogTerminationData(
            applicationState: .active,
            appStartInfo: .empty,
            duringStartup: false,
            memoryWarnings: 2
        )
    }

    func testFanOutToAllReceivers() {
        let first = WatchdogStub()
        let second = WatchdogStub()
        let multi = MultiWatchdogTerminationsReceiver(receivers: [first, second])

        let data = makeData()
        multi.watchdogTerminationReceived(data)

        XCTAssertEqual(first.received.count, 1)
        XCTAssertEqual(second.received.count, 1)
        XCTAssertEqual(first.received.first?.applicationState, data.applicationState)
        XCTAssertEqual(first.received.first?.memoryWarnings, data.memoryWarnings)
    }

    func testEmptyReceiversArrayDoesNotCrash() {
        let multi = MultiWatchdogTerminationsReceiver(receivers: [])
        multi.watchdogTerminationReceived(makeData())
    }

    func testOrderPreserved() {
        var order: [Int] = []
        final class OrderingStub: WatchdogTerminationsReceiver {
            let id: Int
            let onCall: (Int) -> Void
            init(id: Int, onCall: @escaping (Int) -> Void) {
                self.id = id
                self.onCall = onCall
            }
            func watchdogTerminationReceived(_ data: WatchdogTerminationData) {
                onCall(id)
            }
        }
        let multi = MultiWatchdogTerminationsReceiver(receivers: [
            OrderingStub(id: 100, onCall: { order.append($0) }),
            OrderingStub(id: 101, onCall: { order.append($0) }),
        ])
        multi.watchdogTerminationReceived(makeData())

        XCTAssertEqual(order, [100, 101])
    }
}
