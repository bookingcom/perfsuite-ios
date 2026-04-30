//
//  MultiHangsReceiverTests.swift
//  PerformanceSuite-Tests
//
//  Created by Ahmed Nafei on 30/04/2026.
//

import XCTest
@testable import PerformanceSuite

final class MultiHangsReceiverTests: XCTestCase {

    private final class HangStub: HangsReceiver {
        var fatal: [HangInfo] = []
        var nonFatal: [HangInfo] = []
        var started: [HangInfo] = []
        var customThreshold: TimeInterval = 2

        func fatalHangReceived(info: HangInfo) {
            fatal.append(info)
        }
        func nonFatalHangReceived(info: HangInfo) {
            nonFatal.append(info)
        }
        func hangStarted(info: HangInfo) {
            started.append(info)
        }
        var hangThreshold: TimeInterval {
            customThreshold
        }
    }

    func testFanOutFatalNonFatalAndStarted() {
        let first = HangStub()
        let second = HangStub()
        let multi = MultiHangsReceiver(receivers: [first, second])

        let info = HangInfo.with(callStack: "stack", duringStartup: false, duration: .milliseconds(2500))
        multi.hangStarted(info: info)
        multi.nonFatalHangReceived(info: info)
        multi.fatalHangReceived(info: info)

        XCTAssertEqual(first.started.count, 1)
        XCTAssertEqual(second.started.count, 1)
        XCTAssertEqual(first.nonFatal.count, 1)
        XCTAssertEqual(second.nonFatal.count, 1)
        XCTAssertEqual(first.fatal.count, 1)
        XCTAssertEqual(second.fatal.count, 1)
    }

    func testHangThresholdTakenFromFirstReceiver() {
        let first = HangStub()
        first.customThreshold = 5
        let second = HangStub()
        second.customThreshold = 99

        let multi = MultiHangsReceiver(receivers: [first, second])

        XCTAssertEqual(multi.hangThreshold, 5)
    }

    func testHangThresholdIsStableAcrossReceiverThresholdChanges() {
        // The threshold is a config-time value: it's read once at init and used by
        // the detection timer for the lifetime of the reporter. We must not look it
        // up dynamically from the first receiver, otherwise a change after init
        // would silently change behaviour.
        let first = HangStub()
        first.customThreshold = 3
        let multi = MultiHangsReceiver(receivers: [first])
        XCTAssertEqual(multi.hangThreshold, 3)

        first.customThreshold = 60
        XCTAssertEqual(multi.hangThreshold, 3, "Threshold must be captured at init, not re-read")
    }

    func testOrderPreservedForAllMethods() {
        var startedOrder: [Int] = []
        var nonFatalOrder: [Int] = []
        var fatalOrder: [Int] = []

        final class OrderingStub: HangsReceiver {
            let id: Int
            let onStarted: (Int) -> Void
            let onNonFatal: (Int) -> Void
            let onFatal: (Int) -> Void
            init(id: Int,
                 onStarted: @escaping (Int) -> Void,
                 onNonFatal: @escaping (Int) -> Void,
                 onFatal: @escaping (Int) -> Void) {
                self.id = id
                self.onStarted = onStarted
                self.onNonFatal = onNonFatal
                self.onFatal = onFatal
            }
            func hangStarted(info: HangInfo) { onStarted(id) }
            func nonFatalHangReceived(info: HangInfo) { onNonFatal(id) }
            func fatalHangReceived(info: HangInfo) { onFatal(id) }
        }

        let multi = MultiHangsReceiver(receivers: [
            OrderingStub(
                id: 1,
                onStarted: { startedOrder.append($0) },
                onNonFatal: { nonFatalOrder.append($0) },
                onFatal: { fatalOrder.append($0) }
            ),
            OrderingStub(
                id: 2,
                onStarted: { startedOrder.append($0) },
                onNonFatal: { nonFatalOrder.append($0) },
                onFatal: { fatalOrder.append($0) }
            ),
        ])
        let info = HangInfo.with(callStack: "stack", duringStartup: true, duration: .seconds(3))
        multi.hangStarted(info: info)
        multi.nonFatalHangReceived(info: info)
        multi.fatalHangReceived(info: info)

        XCTAssertEqual(startedOrder, [1, 2])
        XCTAssertEqual(nonFatalOrder, [1, 2])
        XCTAssertEqual(fatalOrder, [1, 2])
    }
}
