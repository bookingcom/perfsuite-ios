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

    // MARK: - Live-measurement dispatch (single live child drives the measurement; non-live children get the completed callback)

    func testSingleLiveChildDrivesMeasurementAndRoundTripsHandle() {
        let live = LiveRenderingStub()
        let multi = MultiRenderingMetricsReceiver<String>(
            screenIdentifier: { _ in nil },
            receivers: [live]
        )
        let anchor = Date(timeIntervalSince1970: 1_700_000_000)

        let context = multi.screenRenderingStarted(screen: "y", sessionStarted: anchor)
        XCTAssertNotNil(context)
        multi.screenRenderingEnded(metrics: makeMetrics(), screen: "y", context: context)

        XCTAssertEqual(live.startedScreens.map(\.0), ["y"])
        XCTAssertEqual(live.startedScreens.first?.1, anchor)
        XCTAssertEqual(live.endedContexts.count, 1)
        XCTAssertNotNil(live.endedContexts.first ?? nil)
    }

    func testEmptySessionNotForwardedToNonLiveChildInMixedComposition() {
        // Empty session: live child wants it (empty = signal); legacy child must NOT see it
        // (standalone it'd be dropped).
        let legacy = StringRenderingReceiverStub()
        let live = LiveRenderingStub()
        let multi = MultiRenderingMetricsReceiver<String>(
            screenIdentifier: { _ in nil },
            receivers: [legacy, live]
        )
        let anchor = Date(timeIntervalSince1970: 1_700_000_000)

        // Empty session (no frames): only the live child should be finalised.
        let context = multi.screenRenderingStarted(screen: "y", sessionStarted: anchor)
        multi.screenRenderingEnded(metrics: .zero(sessionStarted: anchor), screen: "y", context: context)

        XCTAssertEqual(live.endedContexts.count, 1, "Live child finalises its measurement on the empty session")
        XCTAssertTrue(legacy.received.isEmpty, "Legacy child must not receive the empty-session callback")

        // A non-empty session reaches both children.
        let context2 = multi.screenRenderingStarted(screen: "y", sessionStarted: anchor)
        multi.screenRenderingEnded(metrics: makeMetrics(), screen: "y", context: context2)

        XCTAssertEqual(live.endedContexts.count, 2)
        XCTAssertEqual(legacy.received.count, 1, "Non-empty session reaches the legacy child")
    }
}

// File-scope so the nested `Ctx` handle stays at one level of nesting (SwiftLint `nesting`).
private final class LiveRenderingStub: LiveRenderingMetricsReceiver {
    final class Ctx: MeasurementHandle { func cancel() {} }
    var startedScreens: [(String, Date)] = []
    var endedContexts: [(any MeasurementHandle)?] = []
    func screenIdentifier(for viewController: UIViewController) -> String? { nil }
    func renderingMetricsReceived(metrics: RenderingMetrics, screen: String) {}
    func screenRenderingStarted(screen: String, sessionStarted: Date) -> (any MeasurementHandle)? {
        startedScreens.append((screen, sessionStarted))
        return Ctx()
    }
    func screenRenderingEnded(metrics: RenderingMetrics, screen: String, context: (any MeasurementHandle)?) {
        endedContexts.append(context)
    }
}
