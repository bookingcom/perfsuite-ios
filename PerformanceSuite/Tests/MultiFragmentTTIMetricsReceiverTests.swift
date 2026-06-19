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

    // MARK: - Live-measurement dispatch (single live child)

    func testSingleLiveChildDrivesMeasurementAndRoundTripsHandle() {
        let live = LiveFragmentReceiverStub()
        let legacy = StringFragmentReceiverStub()
        let multi = MultiFragmentTTIMetricsReceiver<String>(receivers: [live, legacy])

        let context = multi.fragmentTTIMeasurementStarted(fragment: "header")
        XCTAssertNotNil(context)
        multi.fragmentTTIMeasurementEnded(
            metrics: TTIMetrics(tti: .milliseconds(1), ttfr: .milliseconds(1), appStartInfo: .empty),
            fragment: "header",
            context: context
        )

        XCTAssertEqual(live.startedFragments, ["header"])
        XCTAssertEqual(live.endedContexts.count, 1)
        XCTAssertNotNil(live.endedContexts.first ?? nil)
        XCTAssertEqual(legacy.received.count, 1, "Non-live child gets the completed callback")
    }

    func testConcurrentStartsOnDifferentFragmentsHaveIsolatedContexts() {
        let r1 = CountingFragmentReceiverStub()
        let multi = MultiFragmentTTIMetricsReceiver<String>(receivers: [r1])

        let headerCtx = multi.fragmentTTIMeasurementStarted(fragment: "header")
        let footerCtx = multi.fragmentTTIMeasurementStarted(fragment: "footer")

        // Cancelling the header context must not flag the footer context.
        headerCtx?.cancel()

        XCTAssertEqual(r1.spawned.count, 2)
        let header = r1.spawned.first { $0.id == "header" }
        let footer = r1.spawned.first { $0.id == "footer" }
        XCTAssertEqual(header?.cancelled, true)
        XCTAssertEqual(footer?.cancelled, false)
        // Footer context can still be cancelled or finalised independently.
        footerCtx?.cancel()
        XCTAssertEqual(footer?.cancelled, true)
    }
}

// File-scope so the nested `Ctx` handle stays at one level of nesting (SwiftLint `nesting`).
private final class LiveFragmentReceiverStub: LiveFragmentTTIMetricsReceiver {
    final class Ctx: MeasurementHandle {
        func cancel() {}
    }
    var startedFragments: [String] = []
    var endedContexts: [(any MeasurementHandle)?] = []
    func fragmentTTIMetricsReceived(metrics: TTIMetrics, fragment: String) {}
    func fragmentTTIMeasurementStarted(fragment: String) -> (any MeasurementHandle)? {
        startedFragments.append(fragment)
        return Ctx()
    }
    func fragmentTTIMeasurementEnded(metrics: TTIMetrics, fragment: String, context: (any MeasurementHandle)?) {
        endedContexts.append(context)
    }
}

private final class CountingFragmentReceiverStub: LiveFragmentTTIMetricsReceiver {
    final class Ctx: MeasurementHandle {
        let id: String
        var cancelled = false
        init(id: String) { self.id = id }
        func cancel() { cancelled = true }
    }
    var spawned: [Ctx] = []
    func fragmentTTIMetricsReceived(metrics: TTIMetrics, fragment: String) {}
    func fragmentTTIMeasurementStarted(fragment: String) -> (any MeasurementHandle)? {
        let ctx = Ctx(id: fragment)
        spawned.append(ctx)
        return ctx
    }
    func fragmentTTIMeasurementEnded(metrics: TTIMetrics, fragment: String, context: (any MeasurementHandle)?) {}
}
