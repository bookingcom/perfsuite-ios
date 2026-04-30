//
//  MultiFragmentTTIMetricsReceiverTests.swift
//  PerformanceSuite-Tests
//
//  Created by Ahmed Nafei on 30/04/2026.
//

import XCTest
@testable import PerformanceSuite

@available(iOS 16.0, *)
final class MultiFragmentTTIMetricsReceiverTests: XCTestCase {

    // FragmentIdentifier is inferred from the method signature below.
    private final class StringFragmentReceiverStub: FragmentTTIMetricsReceiver {
        var received: [(TTIMetrics, String)] = []
        func fragmentTTIMetricsReceived(metrics: TTIMetrics, fragment: String) {
            received.append((metrics, fragment))
        }
    }

    func testFanOutToAllReceivers() {
        let first = StringFragmentReceiverStub()
        let second = StringFragmentReceiverStub()
        let multi = MultiFragmentTTIMetricsReceiver<String>(receivers: [first, second])

        let metrics = TTIMetrics(tti: .milliseconds(75), ttfr: .milliseconds(10), appStartInfo: .empty)
        multi.fragmentTTIMetricsReceived(metrics: metrics, fragment: "search_filter_panel")

        XCTAssertEqual(first.received.count, 1)
        XCTAssertEqual(first.received.first?.1, "search_filter_panel")
        XCTAssertEqual(first.received.first?.0, metrics)
        XCTAssertEqual(second.received.count, 1)
    }

    func testEmptyReceiversArrayDoesNotCrash() {
        let multi = MultiFragmentTTIMetricsReceiver<String>(receivers: [])
        let metrics = TTIMetrics(tti: .milliseconds(1), ttfr: .milliseconds(1), appStartInfo: .empty)
        multi.fragmentTTIMetricsReceived(metrics: metrics, fragment: "x")
    }

    func testOrderPreserved() {
        var order: [Int] = []
        final class OrderingStub: FragmentTTIMetricsReceiver {
            let id: Int
            let onCall: (Int) -> Void
            init(id: Int, onCall: @escaping (Int) -> Void) {
                self.id = id
                self.onCall = onCall
            }
            func fragmentTTIMetricsReceived(metrics: TTIMetrics, fragment: String) {
                onCall(id)
            }
        }
        let receivers: [any FragmentTTIMetricsReceiver<String>] = [
            OrderingStub(id: 7, onCall: { order.append($0) }),
            OrderingStub(id: 8, onCall: { order.append($0) }),
            OrderingStub(id: 9, onCall: { order.append($0) }),
        ]
        let multi = MultiFragmentTTIMetricsReceiver<String>(receivers: receivers)
        multi.fragmentTTIMetricsReceived(
            metrics: TTIMetrics(tti: .milliseconds(1), ttfr: .milliseconds(1), appStartInfo: .empty),
            fragment: "f"
        )

        XCTAssertEqual(order, [7, 8, 9])
    }
}
