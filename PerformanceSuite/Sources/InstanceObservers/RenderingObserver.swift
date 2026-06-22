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
        registerAppLifecycleObservers()
    }

    private let screen: R.ScreenIdentifier
    private let metricsReceiver: R
    private let framesMeter: FramesMeter


    private var metrics = RenderingMetrics.zero

    /// Live measurement handle returned by `metricsReceiver.screenRenderingStarted`. Stored on
    /// `PerformanceMonitoring.queue`. Consumed at `beforeViewWillDisappear` (success path)
    /// or cancelled at `deinit` if the screen was destroyed before `viewWillDisappear`.
    private var measurementHandle: (any MeasurementHandle)?

    /// Guards out-of-order lifecycle on a synchronous push-then-pop: the swizzler defers viewDidAppear
    /// via main.async but runs viewWillDisappear synchronously, so willDisappear's PM closure can be
    /// queued before didAppear's. Set/read only on PerformanceMonitoring.queue.
    private var didAppearProcessed = false
    private var pendingDisappear = false

    /// True while the live span was ended early by app backgrounding (willResignActive) but the screen
    /// is still on-screen — so didBecomeActive restarts a fresh span and a later real viewWillDisappear
    /// must not double-report. Set/read only on PerformanceMonitoring.queue.
    private var endedForBackground = false
    /// Block-based app-lifecycle observers (RenderingObserver is generic, so it can't expose @objc
    /// selectors). Removed in deinit.
    private var lifecycleObservers: [any NSObjectProtocol] = []

    func beforeInit() {}

    func beforeViewDidLoad() {}

    func afterViewDidAppear() {
        // Capture the wall-clock anchor synchronously before the PerformanceMonitoring.queue hop so
        // both RenderingMetrics.zero(sessionStarted:) and screenRenderingStarted see the true
        // viewDidAppear instant, not the post-hop time.
        let sessionStarted = Date()
        PerformanceMonitoring.queue.async {
            self.metrics = RenderingMetrics.zero(sessionStarted: sessionStarted)
            self.framesMeter.subscribe(receiver: self)
            // Start synchronously on PerformanceMonitoring.queue (where all other observer state is
            // mutated) to avoid racing a beforeViewWillDisappear that lands mid-start. Live receivers
            // build the measurement handle here (thread-safely); only resolved on iOS 16.
            if #available(iOS 16.0, *), let live = self.metricsReceiver as? any LiveRenderingMetricsReceiver<R.ScreenIdentifier> {
                self.measurementHandle = live.screenRenderingStarted(
                    screen: self.screen,
                    sessionStarted: sessionStarted
                )
            }
            self.didAppearProcessed = true
            // Sync-push-pop queued the disappear before setup ran; finish the (zero-length) session now.
            if self.pendingDisappear {
                self.pendingDisappear = false
                self.processDisappear()
            }
        }
    }

    func afterViewWillAppear() {}

    func beforeViewWillDisappear() {
        PerformanceMonitoring.queue.async {
            // didAppear's setup hasn't run yet; park and let it finalize after wiring state.
            guard self.didAppearProcessed else {
                self.pendingDisappear = true
                return
            }
            self.processDisappear()
        }
    }

    static var identifier: AnyObject {
        return renderingObserverIdentifier
    }

    private func processDisappear() {
        dispatchPrecondition(condition: .onQueue(PerformanceMonitoring.queue))
        // If the span was already ended early by backgrounding (and not restarted) it is finished and
        // already unsubscribed — must not unsubscribe or report again. Otherwise this is a normal
        // disappear: unsubscribe the FramesMeter, report, and end the live span.
        if !endedForBackground {
            framesMeter.unsubscribe(receiver: self)
            reportMetricsIfNeeded()
        }
        // Reset the latch + counters so a reused VC instance starts a clean session next appearance.
        // Without this, a second sync push-then-pop runs the disappear before the re-appear setup —
        // re-dispatching stale metrics to a legacy receiver and orphaning the new live measurement.
        didAppearProcessed = false
        endedForBackground = false
        metrics = .zero
    }

    // MARK: - App lifecycle (background-safe live span)

    /// Screen-rendering spans run from viewDidAppear to viewWillDisappear, which can straddle an app
    /// background. Backgrounding fires no viewWillDisappear, so the open span would otherwise be
    /// auto-terminated by the backend (e.g. Embrace, `user_abandon`). End it synchronously on
    /// willResignActive — which precedes the backend's didEnterBackground session-end — and restart it
    /// on didBecomeActive while the screen is still visible. Mirrors AppRenderingReporter's handling.
    private func registerAppLifecycleObservers() {
        let resign = NotificationCenter.default.addObserver(
            forName: UIApplication.willResignActiveNotification, object: nil, queue: nil
        ) { [weak self] _ in self?.handleWillResignActive() }
        let active = NotificationCenter.default.addObserver(
            forName: UIApplication.didBecomeActiveNotification, object: nil, queue: nil
        ) { [weak self] _ in self?.handleDidBecomeActive() }
        lifecycleObservers = [resign, active]
    }

    private func handleWillResignActive() {
        // Synchronous so the live span ends within this notification turn — before the backend ends
        // the session on didEnterBackground and auto-terminates the still-open span.
        PerformanceMonitoring.runOnQueue {
            self.endForBackground()
        }
    }

    private func endForBackground() {
        dispatchPrecondition(condition: .onQueue(PerformanceMonitoring.queue))
        guard didAppearProcessed, let context = measurementHandle, !endedForBackground else { return }
        framesMeter.unsubscribe(receiver: self)
        let metrics = self.metrics
        self.measurementHandle = nil
        self.endedForBackground = true
        // Synchronous finalize to win the race against the backend's session-end auto-termination.
        PerformanceMonitoring.consumerQueue.sync {
            if #available(iOS 16.0, *), let live = self.metricsReceiver as? any LiveRenderingMetricsReceiver<R.ScreenIdentifier> {
                live.screenRenderingEnded(metrics: metrics, screen: self.screen, context: context)
            } else {
                self.metricsReceiver.renderingMetricsReceived(metrics: metrics, screen: self.screen)
            }
        }
    }

    private func handleDidBecomeActive() {
        // Capture the wall-clock anchor synchronously before the queue hop (same as afterViewDidAppear).
        let sessionStarted = Date()
        PerformanceMonitoring.queue.async {
            // Only restart if we ended early for background AND the screen is still appeared.
            guard self.endedForBackground, self.didAppearProcessed else { return }
            self.endedForBackground = false
            self.metrics = RenderingMetrics.zero(sessionStarted: sessionStarted)
            self.framesMeter.subscribe(receiver: self)
            if #available(iOS 16.0, *), let live = self.metricsReceiver as? any LiveRenderingMetricsReceiver<R.ScreenIdentifier> {
                self.measurementHandle = live.screenRenderingStarted(screen: self.screen, sessionStarted: sessionStarted)
            }
        }
    }

    private func reportMetricsIfNeeded() {
        dispatchPrecondition(condition: .onQueue(PerformanceMonitoring.queue))

        let metrics = self.metrics
        let context = self.measurementHandle
        self.measurementHandle = nil
        // Legacy gate: a no-signal session must NOT be reported. `metrics` is seeded as
        // `.zero(sessionStarted:)` (so `!= .zero`); compare against the same-anchor zero to let only
        // counters decide. A live receiver (`context != nil`) bypasses the gate to finalise empty sessions.
        let countersZero: RenderingMetrics
        if let anchor = metrics.sessionStarted {
            countersZero = .zero(sessionStarted: anchor)
        } else {
            countersZero = .zero
        }
        guard metrics != countersZero || context != nil else { return }
        PerformanceMonitoring.consumerQueue.async {
            if #available(iOS 16.0, *), let live = self.metricsReceiver as? any LiveRenderingMetricsReceiver<R.ScreenIdentifier> {
                live.screenRenderingEnded(metrics: metrics, screen: self.screen, context: context)
            } else {
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

    deinit {
        // Observer destroyed before viewWillDisappear (e.g. VC popped without UIKit
        // delivering the willDisappear lifecycle, or a stand-alone observer scope).
        // Discard any live measurement so it never leaks as half-finished. Idempotent.
        lifecycleObservers.forEach { NotificationCenter.default.removeObserver($0) }
        self.measurementHandle?.cancel()
    }
}

private let renderingObserverIdentifier: AnyObject = NSObject()
