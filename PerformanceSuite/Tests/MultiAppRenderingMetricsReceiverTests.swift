//
//  MultiAppRenderingMetricsReceiverTests.swift
//  PerformanceSuite-Tests
//
//  Created by Ahmed Nafei on 30/04/2026.
//

import XCTest
@testable import PerformanceSuite

final class MultiAppRenderingMetricsReceiverTests: XCTestCase {

    private final class AppRenderingStub: AppRenderingMetricsReceiver {
        var received: [RenderingMetrics] = []
        func appRenderingMetricsReceived(metrics: RenderingMetrics) {
            received.append(metrics)
        }
    }

    private func makeMetrics() -> RenderingMetrics {
        RenderingMetrics(
            renderedFrames: 240,
            expectedFrames: 240,
            droppedFrames: 0,
            frozenFrames: 0,
            slowFrames: 0,
            freezeTime: .milliseconds(0),
            sessionDuration: .seconds(4),
            appStartInfo: .empty
        )
    }

    func testFanOutToAllReceivers() {
        let first = AppRenderingStub()
        let second = AppRenderingStub()
        let third = AppRenderingStub()
        let multi = MultiAppRenderingMetricsReceiver(receivers: [first, second, third])

        let metrics = makeMetrics()
        multi.appRenderingMetricsReceived(metrics: metrics)

        XCTAssertEqual(first.received, [metrics])
        XCTAssertEqual(second.received, [metrics])
        XCTAssertEqual(third.received, [metrics])
    }

    func testEmptyReceiversArrayDoesNotCrash() {
        let multi = MultiAppRenderingMetricsReceiver(receivers: [])
        multi.appRenderingMetricsReceived(metrics: makeMetrics())
    }

    func testOrderPreserved() {
        var order: [Int] = []
        final class OrderingStub: AppRenderingMetricsReceiver {
            let id: Int
            let onCall: (Int) -> Void
            init(id: Int, onCall: @escaping (Int) -> Void) {
                self.id = id
                self.onCall = onCall
            }
            func appRenderingMetricsReceived(metrics: RenderingMetrics) {
                onCall(id)
            }
        }
        let multi = MultiAppRenderingMetricsReceiver(receivers: [
            OrderingStub(id: 1, onCall: { order.append($0) }),
            OrderingStub(id: 2, onCall: { order.append($0) }),
        ])
        multi.appRenderingMetricsReceived(metrics: makeMetrics())

        XCTAssertEqual(order, [1, 2])
    }

    // MARK: - Live-measurement dispatch (session start/end reach only the live child)

    func testSessionStartAndEndForwardedOnlyToLiveChild() {
        final class LiveStub: LiveAppRenderingMetricsReceiver {
            var received: [RenderingMetrics] = []
            var startedDates: [Date] = []
            var sessionEndedCount = 0
            func appRenderingMetricsReceived(metrics: RenderingMetrics) { received.append(metrics) }
            func appRenderingSessionStarted(at startedAt: Date) { startedDates.append(startedAt) }
            func appRenderingSessionEnded() { sessionEndedCount += 1 }
        }

        let legacy = AppRenderingStub()
        let live = LiveStub()
        let multi = MultiAppRenderingMetricsReceiver(receivers: [legacy, live])

        let startedAt = Date(timeIntervalSince1970: 1_700_000_000)
        let metrics = makeMetrics()
        multi.appRenderingSessionStarted(at: startedAt)
        multi.appRenderingMetricsReceived(metrics: metrics)
        multi.appRenderingSessionEnded()

        // Chunks fan out to both; session start/end only to the live child.
        XCTAssertEqual(legacy.received, [metrics])
        XCTAssertEqual(live.received, [metrics])
        XCTAssertEqual(live.startedDates, [startedAt])
        XCTAssertEqual(live.sessionEndedCount, 1)
    }
}
