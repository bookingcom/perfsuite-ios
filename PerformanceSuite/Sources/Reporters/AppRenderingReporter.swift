//
//  AppRenderingReporter.swift
//  PerformanceSuite
//
//  Created by Gleb Tarasov on 21/12/2021.
//

import Foundation

/// You should implement this protocol to receive app-level rendering metrics in your code.
///
/// Pass instance of this protocol to the config item `ConfigItem.appLevelRendering`
public protocol AppRenderingMetricsReceiver: AnyObject {
    /// Method is called when app-level performance metrics are calculated.
    ///
    /// `Config.appLevelRendering` should be enabled.
    ///
    /// Method is called on a separate background queue `PerformanceMonitoring.consumerQueue`.
    ///
    /// It is called as soon as some frames were skipped during the rendering, but with some throttling,
    /// to avoid too often calls.
    ///
    /// - Parameters:
    ///   - metrics: calculated rendering metrics
    func appRenderingMetricsReceived(metrics: RenderingMetrics)
}


final class AppRenderingReporter: FramesMeterReceiver, AppMetricsReporter {

    init(metricsReceiver: AppRenderingMetricsReceiver, framesMeter: FramesMeter, sendingThrottleInterval: TimeInterval = 5) {
        self.metricsReceiver = metricsReceiver
        self.framesMeter = framesMeter
        self.sendingThrottleInterval = sendingThrottleInterval

        // delay observing to skip dropped frames on launch
        PerformanceMonitoring.queue.asyncAfter(deadline: .now() + sendingThrottleInterval) {
            framesMeter.subscribe(receiver: self)
        }
    }

    private let metricsReceiver: AppRenderingMetricsReceiver
    private let framesMeter: FramesMeter
    private var metrics = RenderingMetrics.zero
    private var scheduledSending: DispatchWorkItem?
    private let sendingThrottleInterval: TimeInterval

    func frameTicked(frameDuration: CFTimeInterval, refreshRateDuration: CFTimeInterval) {
        dispatchPrecondition(condition: .onQueue(PerformanceMonitoring.queue))
        let currentMetrics = RenderingMetrics.metrics(frameDuration: frameDuration, refreshRateDuration: refreshRateDuration)
        self.metrics = self.metrics + currentMetrics
        guard currentMetrics.droppedFrames > 0 else {
            return
        }
        scheduledSending?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            self?.reportMetrics()
        }
        scheduledSending = workItem
        PerformanceMonitoring.queue.asyncAfter(deadline: .now() + .init(sendingThrottleInterval), execute: workItem)
    }

    func reportMetrics() {
        dispatchPrecondition(condition: .onQueue(PerformanceMonitoring.queue))
        let metrics = self.metrics
        self.metrics = .zero
        PerformanceMonitoring.consumerQueue.async {
            self.metricsReceiver.appRenderingMetricsReceived(metrics: metrics)
        }
    }
}
