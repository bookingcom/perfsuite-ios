//
//  MultiTTIMetricsReceiverTests.swift
//  PerformanceSuite-Tests
//
//  Created by Ahmed Nafei on 30/04/2026.
//

import XCTest
@testable import PerformanceSuite

@available(iOS 16.0, *)
final class MultiTTIMetricsReceiverTests: XCTestCase {

    // screenIdentifier(for:) is never called — Multi overrides it via the init closure;
    // kept un-nested so this stub stays at nesting depth 1 (SwiftLint).
    private final class StringTTIReceiverStub: TTIMetricsReceiver {
        func screenIdentifier(for viewController: UIViewController) -> String? {
            "should-not-be-called"
        }

        var received: [(TTIMetrics, String)] = []
        func ttiMetricsReceived(metrics: TTIMetrics, screen: String) {
            received.append((metrics, screen))
        }
    }

    func testFanOutToAllReceivers() {
        let first = StringTTIReceiverStub()
        let second = StringTTIReceiverStub()
        let third = StringTTIReceiverStub()
        let multi = MultiTTIMetricsReceiver<String>(
            screenIdentifier: { _ in "screen_a" },
            receivers: [first, second, third]
        )

        let metrics = TTIMetrics(tti: .milliseconds(100), ttfr: .milliseconds(20), appStartInfo: .empty)
        multi.ttiMetricsReceived(metrics: metrics, screen: "screen_a")

        XCTAssertEqual(first.received.count, 1)
        XCTAssertEqual(first.received.first?.1, "screen_a")
        XCTAssertEqual(first.received.first?.0, metrics)
        XCTAssertEqual(second.received.count, 1)
        XCTAssertEqual(third.received.count, 1)
    }

    func testScreenIdentifierUsesClosureNotReceivers() {
        let receiver = StringTTIReceiverStub()
        let vc = UIViewController()
        var capturedVC: UIViewController?
        let multi = MultiTTIMetricsReceiver<String>(
            screenIdentifier: { vc in
                capturedVC = vc
                return "screen_from_closure"
            },
            receivers: [receiver]
        )

        let result = multi.screenIdentifier(for: vc)

        XCTAssertEqual(result, "screen_from_closure")
        XCTAssertTrue(capturedVC === vc)
    }

    func testEmptyReceiversArrayDoesNotCrash() {
        let multi = MultiTTIMetricsReceiver<String>(
            screenIdentifier: { _ in nil },
            receivers: []
        )
        let metrics = TTIMetrics(tti: .milliseconds(50), ttfr: .milliseconds(10), appStartInfo: .empty)
        multi.ttiMetricsReceived(metrics: metrics, screen: "anything")
    }

    func testReceiversCalledInProvidedOrder() {
        var order: [Int] = []

        final class OrderingStub: TTIMetricsReceiver {
            let id: Int
            let onCall: (Int) -> Void
            init(id: Int, onCall: @escaping (Int) -> Void) {
                self.id = id
                self.onCall = onCall
            }
            func screenIdentifier(for viewController: UIViewController) -> String? { nil }
            func ttiMetricsReceived(metrics: TTIMetrics, screen: String) {
                onCall(id)
            }
        }

        let receivers: [any TTIMetricsReceiver<String>] = [
            OrderingStub(id: 1, onCall: { order.append($0) }),
            OrderingStub(id: 2, onCall: { order.append($0) }),
            OrderingStub(id: 3, onCall: { order.append($0) }),
        ]
        let multi = MultiTTIMetricsReceiver<String>(
            screenIdentifier: { _ in nil },
            receivers: receivers
        )
        multi.ttiMetricsReceived(
            metrics: TTIMetrics(tti: .seconds(1), ttfr: .milliseconds(500), appStartInfo: .empty),
            screen: "x"
        )

        XCTAssertEqual(order, [1, 2, 3])
    }

    @available(iOS 16.0, *)
    func testSingleLiveChildDrivesMeasurementAndRoundTripsHandle() {
        let live = LiveTTIReceiverStub()
        let legacy = StringTTIReceiverStub()
        let multi = MultiTTIMetricsReceiver<String>(
            screenIdentifier: { _ in nil },
            receivers: [live, legacy]
        )

        let context = multi.screenTTIMeasurementStarted(screen: "x")
        XCTAssertNotNil(context, "Live child's handle is returned")
        let metrics = TTIMetrics(tti: .seconds(1), ttfr: .milliseconds(500), appStartInfo: .empty)
        multi.screenTTIMeasurementEnded(metrics: metrics, screen: "x", context: context)

        XCTAssertEqual(live.startedScreens, ["x"])
        XCTAssertEqual(live.endedContexts.count, 1)
        XCTAssertNotNil(live.endedContexts.first ?? nil)
        // Non-live child gets the completed callback, not a live end.
        XCTAssertEqual(legacy.received.count, 1)
    }
}

// File-scope so the `Ctx` handle stays at one level of nesting (SwiftLint `nesting`).
private final class LiveTTIReceiverStub: LiveTTIMetricsReceiver {
    final class Ctx: MeasurementHandle {
        var cancelCount = 0
        func cancel() { cancelCount += 1 }
    }
    var startedScreens: [String] = []
    var endedContexts: [(any MeasurementHandle)?] = []
    func screenIdentifier(for viewController: UIViewController) -> String? { nil }
    func ttiMetricsReceived(metrics: TTIMetrics, screen: String) {}
    func screenTTIMeasurementStarted(screen: String) -> (any MeasurementHandle)? {
        startedScreens.append(screen)
        return Ctx()
    }
    func screenTTIMeasurementEnded(metrics: TTIMetrics, screen: String, context: (any MeasurementHandle)?) {
        endedContexts.append(context)
    }
}
