//
//  TTIMetricsReceiverStub.swift
//  Pods
//
//  Created by Gleb Tarasov on 21/09/2024.
//

import PerformanceSuite
import UIKit
import XCTest

class TTIMetricsReceiverStub: TTIMetricsReceiver {

    var shouldTrack: (UIViewController) -> Bool = { _ in true }

    func ttiMetricsReceived(metrics: TTIMetrics, screen viewController: UIViewController) {
        ttiCallback(metrics, viewController)
        ttiMetrics = metrics
        lastController = viewController
    }

    func screenIdentifier(for viewController: UIViewController) -> UIViewController? {
        if viewController is UINavigationController
            || viewController is UITabBarController
            || type(of: viewController) == UIViewController.self {
            return nil
        }
        if shouldTrack(viewController) {
            return viewController
        } else {
            return nil
        }
    }

    var ttiCallback: (TTIMetrics, UIViewController) -> Void = { (_, _) in }
    var ttiMetrics: TTIMetrics?
    var lastController: UIViewController?
}

/// Live TTI receiver double. Modelled on `LiveRenderingMetricsReceiverStub` in `RenderingObserverTests`.
final class LiveTTIMetricsReceiverStub: LiveTTIMetricsReceiver {

    final class StubContext: MeasurementHandle {
        var cancelCount = 0
        func cancel() { cancelCount += 1 }
    }

    var startedContexts: [StubContext] = []
    var endedContexts: [(any MeasurementHandle)?] = []
    var ttiMetrics: TTIMetrics?

    func screenIdentifier(for viewController: UIViewController) -> UIViewController? {
        return viewController
    }

    func ttiMetricsReceived(metrics: TTIMetrics, screen: UIViewController) {
        // A live receiver always resolves to `screenTTIMeasurementEnded`; the plain callback must not fire.
        XCTFail("ttiMetricsReceived should not fire for a live receiver")
    }

    func screenTTIMeasurementStarted(screen: UIViewController) -> (any MeasurementHandle)? {
        let context = StubContext()
        startedContexts.append(context)
        return context
    }

    func screenTTIMeasurementEnded(
        metrics: TTIMetrics,
        screen: UIViewController,
        context: (any MeasurementHandle)?
    ) {
        endedContexts.append(context)
        ttiMetrics = metrics
    }
}

/// Live TTI receiver that opens pending measurements (`screenIsBeingCreated()`) and records what happens to them.
final class PendingTTIMetricsReceiverStub: LiveTTIMetricsReceiver {

    final class Handle: MeasurementHandle {
        var cancelCount = 0
        func cancel() { cancelCount += 1 }
    }

    struct PendingEnd {
        let handle: Handle
        let reason: PendingScreenTTIEndReason
    }

    /// Screens the receiver tracks when PerformanceSuite resolves them itself (`enable`).
    var trackedScreen: (UIViewController) -> Bool = { _ in false }
    var opensPendingMeasurements = true
    var acceptsAdoption = true

    private(set) var pendingStarts: [Handle] = []
    private(set) var pendingStartDates: [Date] = []
    private(set) var adoptedHandles: [Handle] = []
    private(set) var pendingEnds: [PendingEnd] = []
    private(set) var startedHandles: [Handle] = []
    private(set) var endedContexts: [(any MeasurementHandle)?] = []
    private(set) var ttiMetrics: TTIMetrics?
    private(set) var lastController: UIViewController?

    func screenIdentifier(for viewController: UIViewController) -> UIViewController? {
        trackedScreen(viewController) ? viewController : nil
    }

    func ttiMetricsReceived(metrics: TTIMetrics, screen: UIViewController) {
        XCTFail("ttiMetricsReceived should not fire for a live receiver")
    }

    func screenTTIMeasurementStarted(screen: UIViewController) -> (any MeasurementHandle)? {
        let handle = Handle()
        startedHandles.append(handle)
        return handle
    }

    func screenTTIMeasurementEnded(metrics: TTIMetrics, screen: UIViewController, context: (any MeasurementHandle)?) {
        endedContexts.append(context)
        ttiMetrics = metrics
        lastController = screen
    }

    func screenTTIPendingMeasurementStarted(at startTime: Date) -> (any MeasurementHandle)? {
        guard opensPendingMeasurements else { return nil }
        let handle = Handle()
        pendingStarts.append(handle)
        pendingStartDates.append(startTime)
        return handle
    }

    func screenTTIPendingMeasurementAdopted(_ pending: any MeasurementHandle, screen: UIViewController) -> (any MeasurementHandle)? {
        guard let handle = pending as? Handle else {
            XCTFail("adopted a handle the receiver didn't open")
            return nil
        }
        adoptedHandles.append(handle)
        return acceptsAdoption ? handle : nil
    }

    func screenTTIPendingMeasurementEnded(_ pending: any MeasurementHandle, reason: PendingScreenTTIEndReason) {
        guard let handle = pending as? Handle else {
            XCTFail("ended a handle the receiver didn't open")
            return
        }
        pendingEnds.append(PendingEnd(handle: handle, reason: reason))
    }
}
