//
//  AppRenderingSessionAccumulator.swift
//  PerformanceSuiteOTel
//
//  Created by Ahmed Nafei on 09/06/2026.
//

import Foundation
import OpenTelemetryApi

#if canImport(PerformanceSuiteOTel)
import PerformanceSuite
#endif

/// Owns the open `app-rendering` live span for each foreground session. `AppRenderingReporter` drives
/// the lifecycle on `PerformanceMonitoring.consumerQueue` (start → chunks → end). With
/// `Experiments.fixFatalHangOnResignActive` it also ends the span itself when the app resigns active; the end
/// delivered afterwards is then a no-op. The span carries the caller-injected auto-termination attribute
/// (if any) for unclean exits. Chunks before the first start are dropped.
final class AppRenderingSessionAccumulator {

    private let emitter: OTelSpanEmitter
    private let now: () -> Date
    private let appStateListener: AppStateListener

    /// Guards sessionStartedAt/activeSpan/accumulated across emitter calls: a concurrent chunk must
    /// not setAttribute on a span another path already ended (OTel silently drops such writes).
    private let lock = NSLock()
    private var sessionStartedAt: Date?
    private var activeSpan: (any OpenTelemetryApi.Span)?
    private var accumulated: RenderingMetrics = .zero

    init(
        emitter: OTelSpanEmitter,
        now: @escaping () -> Date = Date.init,
        appStateListener: AppStateListener = DefaultAppStateListener()
    ) {
        self.emitter = emitter
        self.now = now
        self.appStateListener = appStateListener
        // Ends the open span before a backend auto-terminates it when its session ends on didEnterBackground.
        appStateListener.willChange = { [weak self, weak appStateListener] in
            // fixFatalHangOnResignActive: keep on cleanup, without the flag check.
            // Still in the foreground in `willChange`: the app is resigning active.
            if PerformanceMonitoring.experiments.fixFatalHangOnResignActive, appStateListener?.isInBackground == false {
                self?.appRenderingSessionEnded()
            }
        }
    }

    deinit {
        // End outside the lock so a slow tracer hook can't stall deinit.
        lock.lock()
        let pending = activeSpan
        activeSpan = nil
        lock.unlock()
        if let span = pending, span.isRecording {
            span.status = .error(description: "accumulator_deinit")
            span.end()
        }
    }

    /// Re-applies cumulative counters to the live span so an auto-terminated span ships latest data.
    func appRenderingMetricsReceived(metrics: RenderingMetrics) {
        lock.lock()
        defer { lock.unlock() }
        accumulated = accumulated + metrics
        if let span = activeSpan {
            emitter.applyRenderingAttributes(span: span, metrics: accumulated)
        }
    }

    /// Opens the session span, anchored at the reporter-captured `didBecomeActive` instant. Idempotent
    /// (a stray start while open is a no-op); FIFO delivery guarantees the prior close lands first.
    func appRenderingSessionStarted(at startedAt: Date) {
        lock.lock()
        defer { lock.unlock() }
        guard activeSpan == nil else { return }
        sessionStartedAt = startedAt
        accumulated = .zero
        activeSpan = emitter.startAppRenderingLiveSpan(sessionStartedAt: startedAt)
    }

    /// Finalises the open span; idempotent when no session is open.
    func appRenderingSessionEnded() {
        let endedAt = now()
        lock.lock()
        defer { lock.unlock() }
        guard let span = activeSpan, let started = sessionStartedAt else {
            accumulated = .zero
            sessionStartedAt = nil
            return
        }
        let metricsSnapshot = accumulated
        activeSpan = nil
        sessionStartedAt = nil
        accumulated = .zero
        // No `metrics != .zero` gate — empty sessions are signal.
        emitter.finalizeAppRenderingLiveSpan(
            span: span,
            metrics: metricsSnapshot,
            sessionStartedAt: started,
            sessionEndedAt: endedAt
        )
    }
}
