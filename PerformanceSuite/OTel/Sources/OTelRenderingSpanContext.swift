//
//  OTelRenderingSpanContext.swift
//  PerformanceSuiteOTel
//
//  Created by Gleb Tarasov on 20/11/2026.
//

import Foundation
import OpenTelemetryApi

#if canImport(PerformanceSuiteOTel)
import PerformanceSuite
#endif

/// Live screen-rendering span that ends itself with its metrics so far when the app resigns active, before a backend
/// auto-terminates it when its session ends on didEnterBackground. Called from any thread; whichever end comes
/// first wins and the others are no-ops.
final class OTelRenderingSpanContext: MeasurementHandle {
    let span: any OpenTelemetryApi.Span

    private let emitter: OTelSpanEmitter
    private let now: () -> Date
    private let liveMetrics: LiveRenderingMetrics
    private let appStateListener: AppStateListener
    private let lock = NSLock()
    private var isEnded = false

    init(
        span: any OpenTelemetryApi.Span,
        emitter: OTelSpanEmitter,
        now: @escaping () -> Date,
        liveMetrics: LiveRenderingMetrics,
        appStateListener: AppStateListener
    ) {
        self.span = span
        self.emitter = emitter
        self.now = now
        self.liveMetrics = liveMetrics
        self.appStateListener = appStateListener
        appStateListener.willChange = { [weak self, weak appStateListener] in
            // Still in the foreground in `willChange`: the app is resigning active.
            if appStateListener?.isInBackground == false {
                self?.end()
            }
        }
    }

    /// Ends the span with its metrics so far; PerformanceSuite stops updating them when the measurement ends.
    func end() {
        lock.lock()
        guard !isEnded else {
            lock.unlock()
            return
        }
        isEnded = true
        lock.unlock()
        emitter.applyRenderingAttributes(span: span, metrics: liveMetrics.current)
        span.end(time: now())
    }

    func cancel() {
        lock.lock()
        guard !isEnded else {
            lock.unlock()
            return
        }
        isEnded = true
        lock.unlock()
        guard span.isRecording else { return }
        span.status = .error(description: "measurement_cancelled")
        span.end()
    }
}
