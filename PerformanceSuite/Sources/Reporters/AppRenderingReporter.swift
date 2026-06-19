//
//  AppRenderingReporter.swift
//  PerformanceSuite
//
//  Created by Gleb Tarasov on 21/12/2021.
//

import Foundation
import UIKit

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

/// Opt-in live-measurement variant of ``AppRenderingMetricsReceiver``. The reporter drives the whole
/// per-foreground-session lifecycle on `PerformanceMonitoring.consumerQueue` — start, chunks, end —
/// so start/end stay FIFO-ordered (a fast background→foreground can't open a new session before the
/// previous one closes). Callbacks must not block main or `PerformanceMonitoring.queue` (`willTerminate`
/// delivers synchronously). No associated type → no iOS-16 requirement.
public protocol LiveAppRenderingMetricsReceiver: AppRenderingMetricsReceiver {
    func appRenderingSessionStarted(at startedAt: Date)
    func appRenderingSessionEnded()
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

        // The reporter drives the live receiver's whole session lifecycle (start/chunks/end) on
        // consumerQueue, so the receiver registers no UIApplication observers itself — keeping start
        // and end FIFO-ordered on one serial queue.
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appDidBecomeActive),
            name: UIApplication.didBecomeActiveNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appDidEnterBackground),
            name: UIApplication.didEnterBackgroundNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appWillTerminate),
            name: UIApplication.willTerminateNotification,
            object: nil
        )
    }

    deinit {
        // iOS 9+ auto-removes NotificationCenter observers on dealloc; this explicit
        // removeObserver is defensive and keeps the cleanup intent obvious.
        NotificationCenter.default.removeObserver(self)
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

    /// Drains the pending throttled chunk, then signals session-end (FIFO on serial consumerQueue:
    /// queued chunks → drain chunk → end). `synchronously` is `true` only for `willTerminate` (must
    /// finish before the process dies); `didEnterBackground` is async to keep the transition off main
    /// and avoid a `main → PM.queue → consumerQueue → main` deadlock. A finalize that misses
    /// suspension is covered by the caller-injected auto-termination attribute.
    private func drainAndEndSession(synchronously: Bool) {
        PerformanceMonitoring.runOnQueue {
            self.scheduledSending?.cancel()
            self.scheduledSending = nil
            let metrics = self.metrics
            self.metrics = .zero
            let deliver = {
                if metrics != .zero {
                    self.metricsReceiver.appRenderingMetricsReceived(metrics: metrics)
                }
                (self.metricsReceiver as? LiveAppRenderingMetricsReceiver)?.appRenderingSessionEnded()
            }
            if synchronously {
                PerformanceMonitoring.consumerQueue.sync(execute: deliver)
            } else {
                PerformanceMonitoring.consumerQueue.async(execute: deliver)
            }
        }
    }

    @objc private func appDidBecomeActive() {
        // Capture start on main; deliver on consumerQueue so it's FIFO-ordered after a prior session's close.
        let startedAt = Date()
        PerformanceMonitoring.consumerQueue.async {
            (self.metricsReceiver as? LiveAppRenderingMetricsReceiver)?.appRenderingSessionStarted(at: startedAt)
        }
    }

    @objc private func appDidEnterBackground() {
        drainAndEndSession(synchronously: false)
    }

    @objc private func appWillTerminate() {
        drainAndEndSession(synchronously: true)
    }
}
