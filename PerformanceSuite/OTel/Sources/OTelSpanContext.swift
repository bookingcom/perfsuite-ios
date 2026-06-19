//
//  OTelSpanContext.swift
//  PerformanceSuiteOTel
//

import Foundation
import OpenTelemetryApi

#if canImport(PerformanceSuiteOTel)
import PerformanceSuite
#endif

/// Bridges OTel `Span` to `MeasurementHandle`: owns the in-progress span so the emitter
/// can read `ctx.span` at finalize and the SDK can `cancel()` without knowing OTel. `cancel()` is
/// idempotent — the `isRecording` guard absorbs a late cancel after a clean `span.end()` at finalize.
final class OTelSpanContext: MeasurementHandle {
    let span: any OpenTelemetryApi.Span

    init(span: any OpenTelemetryApi.Span) {
        self.span = span
    }

    func cancel() {
        guard span.isRecording else { return }
        span.status = .error(description: "measurement_cancelled")
        span.end()
    }
}
