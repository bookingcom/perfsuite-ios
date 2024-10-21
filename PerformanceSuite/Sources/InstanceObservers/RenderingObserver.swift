//
//  RenderingObserver.swift
//  PerformanceSuite
//
//  Created by Gleb Tarasov on 06/07/2021.
//

import UIKit

final class RenderingObserver<R: RenderingMetricsReceiver>: ViewControllerInstanceObserver, FramesMeterReceiver {

    init(
        screen: R.ScreenIdentifier,
        metricsReceiver: R,
        framesMeter: FramesMeter
    ) {
        self.screen = screen
        self.metricsReceiver = metricsReceiver
        self.framesMeter = framesMeter
    }

    private let screen: R.ScreenIdentifier
    private let metricsReceiver: R
    private let framesMeter: FramesMeter


    private var metrics = RenderingMetrics.zero

    func beforeInit() {}

    func beforeViewDidLoad() {}

    func afterViewDidAppear() {
        PerformanceMonitoring.queue.async {
            self.metrics = RenderingMetrics.zero
            self.framesMeter.subscribe(receiver: self)
        }
    }

    func afterViewWillAppear() {}

    func beforeViewWillDisappear() {
        PerformanceMonitoring.queue.async {
            self.framesMeter.unsubscribe(receiver: self)
            self.reportMetricsIfNeeded()
        }
    }

    static var identifier: AnyObject {
        return renderingObserverIdentifier
    }

    private func reportMetricsIfNeeded() {
        dispatchPrecondition(condition: .onQueue(PerformanceMonitoring.queue))

        let metrics = self.metrics
        if metrics != .zero {
            PerformanceMonitoring.consumerQueue.async {
                self.metricsReceiver.renderingMetricsReceived(metrics: metrics, screen: self.screen)
            }
        }

    }

    // MARK: - FramesMeterReceiver

    func frameTicked(frameDuration: CFTimeInterval, refreshRateDuration: CFTimeInterval) {
        dispatchPrecondition(condition: .onQueue(PerformanceMonitoring.queue))
        let currentMetrics = RenderingMetrics.metrics(frameDuration: frameDuration, refreshRateDuration: refreshRateDuration)
        self.metrics = self.metrics + currentMetrics
    }
}

private let renderingObserverIdentifier: AnyObject = NSObject()
