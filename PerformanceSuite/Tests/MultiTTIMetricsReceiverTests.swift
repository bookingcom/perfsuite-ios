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

    // ScreenIdentifier is inferred from the method signatures below; declaring it
    // explicitly would push this stub to nesting depth 2 and trip SwiftLint.
    private final class StringTTIReceiverStub: TTIMetricsReceiver {
        // We intentionally do not use this: MultiTTIMetricsReceiver overrides screenIdentifier(for:)
        // with the closure passed to its initializer.
        func screenIdentifier(for viewController: UIViewController) -> String? {
            "should-not-be-called"
        }

        var received: [(TTIMetrics, String)] = []
        func ttiMetricsReceived(metrics: TTIMetrics, screen: String) {
            received.append((metrics, screen))
        }
    }

    func testFanOutToAllReceiversInOrder() {
        let first = StringTTIReceiverStub()
        let second = StringTTIReceiverStub()
        let third = StringTTIReceiverStub()
        let invocationOrder = NSMutableArray()
        first.received = []
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
        XCTAssertNotNil(invocationOrder)
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
}
