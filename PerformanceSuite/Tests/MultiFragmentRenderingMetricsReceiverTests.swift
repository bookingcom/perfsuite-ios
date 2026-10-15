//
//  MultiFragmentRenderingMetricsReceiverTests.swift
//  PerformanceSuite-Tests
//
//  Created by Luis Resende on 12/10/2026.
//

import XCTest
@testable import PerformanceSuite

@available(iOS 16.0, *)
final class MultiFragmentRenderingReceiverTests: XCTestCase {

    private final class StringFragmentReceiverStub: FragmentRenderingMetricsReceiver {
        var received: [(RenderingMetrics, String)] = []
        func fragmentRenderingMetricsReceived(metrics: RenderingMetrics, fragment: String) {
            received.append((metrics, fragment))
        }
    }

    func testFanOutToAllReceivers() {
        let first = StringFragmentReceiverStub()
        let second = StringFragmentReceiverStub()
        let multi = MultiFragmentRenderingMetricsReceiver<String>(receivers: [first, second])

        let metrics = RenderingMetrics.zero
        multi.fragmentRenderingMetricsReceived(metrics: metrics, fragment: "supplier_details")

        XCTAssertEqual(first.received.count, 1)
        XCTAssertEqual(first.received.first?.1, "supplier_details")
        XCTAssertEqual(second.received.count, 1)
    }

    func testEmptyReceiversArrayDoesNotCrash() {
        let multi = MultiFragmentRenderingMetricsReceiver<String>(receivers: [])
        multi.fragmentRenderingMetricsReceived(metrics: .zero, fragment: "x")
    }

    func testOrderPreserved() {
        var order: [Int] = []
        final class OrderingStub: FragmentRenderingMetricsReceiver {
            let id: Int
            let onCall: (Int) -> Void
            init(id: Int, onCall: @escaping (Int) -> Void) {
                self.id = id
                self.onCall = onCall
            }
            func fragmentRenderingMetricsReceived(metrics: RenderingMetrics, fragment: String) {
                onCall(id)
            }
        }
        let receivers: [any FragmentRenderingMetricsReceiver<String>] = [
            OrderingStub(id: 7, onCall: { order.append($0) }),
            OrderingStub(id: 8, onCall: { order.append($0) }),
            OrderingStub(id: 9, onCall: { order.append($0) }),
        ]
        let multi = MultiFragmentRenderingMetricsReceiver<String>(receivers: receivers)
        multi.fragmentRenderingMetricsReceived(metrics: .zero, fragment: "f")

        XCTAssertEqual(order, [7, 8, 9])
    }

    // MARK: - Live-measurement dispatch

    func testSingleLiveChildDrivesMeasurementAndRoundTripsHandle() {
        let live = LiveFragmentRenderingReceiverStub()
        let legacy = StringFragmentReceiverStub()
        let multi = MultiFragmentRenderingMetricsReceiver<String>(receivers: [live, legacy])

        let context = multi.fragmentRenderingStarted(fragment: "header")
        XCTAssertNotNil(context)
        multi.fragmentRenderingEnded(metrics: .zero, fragment: "header", context: context)

        XCTAssertEqual(live.startedFragments, ["header"])
        XCTAssertEqual(live.endedContexts.count, 1)
        XCTAssertNotNil(live.endedContexts.first ?? nil)
        XCTAssertEqual(legacy.received.count, 1, "Non-live child gets the completed callback")
    }
}

private final class LiveFragmentRenderingReceiverStub: LiveFragmentRenderingMetricsReceiver {
    final class Ctx: MeasurementHandle {
        func cancel() {}
    }
    var startedFragments: [String] = []
    var endedContexts: [(any MeasurementHandle)?] = []
    func fragmentRenderingMetricsReceived(metrics: RenderingMetrics, fragment: String) {}
    func fragmentRenderingStarted(fragment: String) -> (any MeasurementHandle)? {
        startedFragments.append(fragment)
        return Ctx()
    }
    func fragmentRenderingEnded(metrics: RenderingMetrics, fragment: String, context: (any MeasurementHandle)?) {
        endedContexts.append(context)
    }
}
