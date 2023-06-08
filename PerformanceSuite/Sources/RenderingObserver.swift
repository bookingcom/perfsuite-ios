//
//  RenderingObserver.swift
//  PerformanceSuite
//
//  Created by Gleb Tarasov on 06/07/2021.
//

import UIKit

final class RenderingObserver: ViewControllerObserver, FramesMeterReceiver {

    init(metricsReceiver: RenderingMetricsReceiver, framesMeter: FramesMeter) {
        self.metricsReceiver = metricsReceiver
        self.framesMeter = framesMeter
    }

    private let metricsReceiver: RenderingMetricsReceiver
    private let framesMeter: FramesMeter
    private weak var viewController: UIViewController?

    private var metrics = RenderingMetrics.zero

    func beforeInit(viewController: UIViewController) {
        PerformanceSuite.queue.async {
            assert(self.viewController == nil)
            self.viewController = viewController
        }
    }

    func beforeViewDidLoad(viewController: UIViewController) {}

    func afterViewDidAppear(viewController: UIViewController) {
        PerformanceSuite.queue.async {
            assert(self.viewController === viewController)
            self.metrics = RenderingMetrics.zero
            self.framesMeter.subscribe(receiver: self)
        }
    }

    func afterViewWillAppear(viewController: UIViewController) {}

    func beforeViewWillDisappear(viewController: UIViewController) {
        PerformanceSuite.queue.async {
            assert(self.viewController === viewController)
            self.framesMeter.unsubscribe(receiver: self)
            self.reportMetricsIfNeeded()
        }
    }

    func beforeViewDidDisappear(viewController: UIViewController) {}

    private func reportMetricsIfNeeded() {
        dispatchPrecondition(condition: .onQueue(PerformanceSuite.queue))
        guard let viewController = self.viewController else {
            return
        }

        let metrics = self.metrics
        if metrics != .zero {
            PerformanceSuite.consumerQueue.async {
                self.metricsReceiver.renderingMetricsReceived(metrics: metrics, viewController: viewController)
            }
        }

    }

    // MARK: - FramesMeterReceiver

    func frameTicked(frameDuration: CFTimeInterval, refreshRateDuration: CFTimeInterval) {
        dispatchPrecondition(condition: .onQueue(PerformanceSuite.queue))
        let currentMetrics = RenderingMetrics.metrics(frameDuration: frameDuration, refreshRateDuration: refreshRateDuration)
        self.metrics = self.metrics + currentMetrics
    }
}
