//
//  MultiRenderingMetricsReceiverTests.swift
//  PerformanceSuite-Tests
//
//  Created by Ahmed Nafei on 30/04/2026.
//

import XCTest
@testable import PerformanceSuite

@available(iOS 16.0, *)
final class MultiRenderingMetricsReceiverTests: XCTestCase {

    // ScreenIdentifier is inferred from the method signatures below.
    private final class StringRenderingReceiverStub: RenderingMetricsReceiver {
        func screenIdentifier(for viewController: UIViewController) -> String? {
            "should-not-be-called"
        }

        var received: [(RenderingMetrics, String)] = []
        func renderingMetricsReceived(metrics: RenderingMetrics, screen: String) {
            received.append((metrics, screen))
        }
    }

    private func makeMetrics() -> RenderingMetrics {
        RenderingMetrics(
            renderedFrames: 100,
            expectedFrames: 100,
            droppedFrames: 0,
            frozenFrames: 0,
            slowFrames: 0,
            freezeTime: .milliseconds(0),
            sessionDuration: .seconds(2),
            appStartInfo: .empty
        )
    }

    func testFanOutToAllReceivers() {
        let first = StringRenderingReceiverStub()
        let second = StringRenderingReceiverStub()
        let multi = MultiRenderingMetricsReceiver<String>(
            screenIdentifier: { _ in "home" },
            receivers: [first, second]
        )

        let metrics = makeMetrics()
        multi.renderingMetricsReceived(metrics: metrics, screen: "home")

        XCTAssertEqual(first.received.count, 1)
        XCTAssertEqual(second.received.count, 1)
        XCTAssertEqual(first.received.first?.1, "home")
        XCTAssertEqual(first.received.first?.0, metrics)
    }

    func testScreenIdentifierUsesClosure() {
        let receiver = StringRenderingReceiverStub()
        let multi = MultiRenderingMetricsReceiver<String>(
            screenIdentifier: { _ in "screen_from_closure" },
            receivers: [receiver]
        )

        XCTAssertEqual(multi.screenIdentifier(for: UIViewController()), "screen_from_closure")
    }

    func testEmptyReceiversArrayDoesNotCrash() {
        let multi = MultiRenderingMetricsReceiver<String>(
            screenIdentifier: { _ in nil },
            receivers: []
        )
        multi.renderingMetricsReceived(metrics: makeMetrics(), screen: "x")
    }

    func testOrderPreserved() {
        var order: [Int] = []
        final class OrderingStub: RenderingMetricsReceiver {
            let id: Int
            let onCall: (Int) -> Void
            init(id: Int, onCall: @escaping (Int) -> Void) {
                self.id = id
                self.onCall = onCall
            }
            func screenIdentifier(for viewController: UIViewController) -> String? { nil }
            func renderingMetricsReceived(metrics: RenderingMetrics, screen: String) {
                onCall(id)
            }
        }
        let receivers: [any RenderingMetricsReceiver<String>] = [
            OrderingStub(id: 5, onCall: { order.append($0) }),
            OrderingStub(id: 6, onCall: { order.append($0) }),
        ]
        let multi = MultiRenderingMetricsReceiver<String>(
            screenIdentifier: { _ in nil },
            receivers: receivers
        )
        multi.renderingMetricsReceived(metrics: makeMetrics(), screen: "y")

        XCTAssertEqual(order, [5, 6])
    }
}
