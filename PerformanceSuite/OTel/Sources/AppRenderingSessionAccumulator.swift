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
    private let makeAppStateListener: () -> AppStateListener

    /// Guards sessionStartedAt/activeSpan/accumulated across emitter calls: a concurrent chunk must
    /// not setAttribute on a span another path already ended (OTel silently drops such writes).
    private let lock = NSLock()
    private var sessionStartedAt: Date?
    private var activeSpan: (any OpenTelemetryApi.Span)?
    private var accumulated: RenderingMetrics = .zero
    private var appStateListener: AppStateListener?
    private var liveMetrics: LiveRenderingMetrics?
    /// With `Experiments.fixFatalHangOnResignActive` the tracer is called outside `lock`: a start creating its
    /// span, and an end requested meanwhile, which ends that span as soon as it exists.
    private var isStartingSession = false
    private var isEndRequested = false

    init(
        emitter: OTelSpanEmitter,
        now: @escaping () -> Date = Date.init,
        makeAppStateListener: @escaping () -> AppStateListener = { DefaultAppStateListener() }
    ) {
        self.emitter = emitter
        self.now = now
        self.makeAppStateListener = makeAppStateListener
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
        if PerformanceMonitoring.experiments.fixFatalHangOnResignActive {
            // fixFatalHangOnResignActive: variant implementation; keep on cleanup.
            lock.lock()
            let span = activeSpan
            let liveMetrics = self.liveMetrics
            lock.unlock()
            if let span, let liveMetrics {
                emitter.applyRenderingAttributes(span: span, metrics: liveMetrics.current)
            }
        } else {
            // fixFatalHangOnResignActive: base implementation; remove on cleanup, with `accumulated`.
            lock.lock()
            defer { lock.unlock() }
            accumulated = accumulated + metrics
            if let span = activeSpan {
                emitter.applyRenderingAttributes(span: span, metrics: accumulated)
            }
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

    // fixFatalHangOnResignActive: variant implementation; keep on cleanup, replacing `appRenderingSessionStarted(at:)`.
    /// Like `appRenderingSessionStarted(at:)`, and ends the span itself with `liveMetrics` when the app resigns active.
    func appRenderingSessionStarted(at startedAt: Date, liveMetrics: LiveRenderingMetrics) {
        // Here rather than in `init`: nothing should observe the app before PerformanceSuite is enabled,
        // and receivers are created before `PerformanceMonitoring.enable`.
        observeResignActiveIfNeeded()
        lock.lock()
        guard activeSpan == nil, !isStartingSession else {
            lock.unlock()
            return
        }
        isStartingSession = true
        self.liveMetrics = liveMetrics
        sessionStartedAt = startedAt
        lock.unlock()

        let span = emitter.startAppRenderingLiveSpan(sessionStartedAt: startedAt)

        lock.lock()
        isStartingSession = false
        guard isEndRequested else {
            activeSpan = span
            lock.unlock()
            return
        }
        isEndRequested = false
        sessionStartedAt = nil
        lock.unlock()
        emitter.finalizeAppRenderingLiveSpan(
            span: span,
            metrics: liveMetrics.current,
            sessionStartedAt: startedAt,
            sessionEndedAt: now()
        )
    }

    /// Ends the open span before a backend auto-terminates it when its session ends on didEnterBackground.
    /// Called on `consumerQueue` only, like the other session callbacks.
    private func observeResignActiveIfNeeded() {
        guard appStateListener == nil else { return }
        let listener = makeAppStateListener()
        listener.willChange = { [weak self, weak listener] in
            // Still in the foreground in `willChange`: the app is resigning active.
            if listener?.isInBackground == false {
                self?.appRenderingSessionEnded()
            }
        }
        appStateListener = listener
    }

    /// Finalises the open span; idempotent when no session is open.
    func appRenderingSessionEnded() {
        if PerformanceMonitoring.experiments.fixFatalHangOnResignActive {
            // fixFatalHangOnResignActive: variant implementation; keep on cleanup.
            endSession()
        } else {
            // fixFatalHangOnResignActive: base implementation; remove on cleanup.
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

    /// Takes the open span under `lock` and finalizes it outside, so ending on main never waits for the tracer.
    private func endSession() {
        let endedAt = now()
        lock.lock()
        guard let span = activeSpan, let started = sessionStartedAt, let liveMetrics else {
            isEndRequested = isStartingSession
            lock.unlock()
            return
        }
        activeSpan = nil
        sessionStartedAt = nil
        lock.unlock()
        // No `metrics != .zero` gate — empty sessions are signal.
        emitter.finalizeAppRenderingLiveSpan(
            span: span,
            metrics: liveMetrics.current,
            sessionStartedAt: started,
            sessionEndedAt: endedAt
        )
    }
}
