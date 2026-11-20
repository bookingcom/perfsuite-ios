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

/// Live screen-rendering span that ends itself with its latest metrics when the app resigns active, before a backend
/// auto-terminates it when its session ends on didEnterBackground. Called from any thread; whichever end comes
/// first wins and the others are no-ops.
final class OTelRenderingSpanContext: MeasurementHandle {
    let span: any OpenTelemetryApi.Span

    private let emitter: OTelSpanEmitter
    private let now: () -> Date
    private let appStateListener: AppStateListener
    private let lock = NSLock()
    private var latestMetrics: RenderingMetrics?
    private var isEnded = false

    init(span: any OpenTelemetryApi.Span, emitter: OTelSpanEmitter, now: @escaping () -> Date, appStateListener: AppStateListener) {
        self.span = span
        self.emitter = emitter
        self.now = now
        self.appStateListener = appStateListener
        appStateListener.willChange = { [weak self, weak appStateListener] in
            if appStateListener?.isInBackground == true {
                self?.end(metrics: nil)
            }
        }
    }

    /// Keeps `metrics` for an end when the app resigns active, and applies them so an auto-terminated span has them too.
    func update(metrics: RenderingMetrics) {
        lock.lock()
        guard !isEnded else {
            lock.unlock()
            return
        }
        latestMetrics = metrics
        lock.unlock()
        emitter.applyRenderingAttributes(span: span, metrics: metrics)
    }

    /// Ends the span with `metrics`, or with the latest updated ones when `nil`.
    func end(metrics: RenderingMetrics?) {
        lock.lock()
        guard !isEnded else {
            lock.unlock()
            return
        }
        isEnded = true
        let metrics = metrics ?? latestMetrics
        lock.unlock()
        if let metrics {
            emitter.applyRenderingAttributes(span: span, metrics: metrics)
        }
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
