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
