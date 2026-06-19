//
//  OTelSpanEmitter+AppSessionRendering.swift
//  PerformanceSuiteOTel
//
//  Created by Ahmed Nafei on 09/06/2026.
//

import Foundation
import OpenTelemetryApi

#if canImport(PerformanceSuiteOTel)
import PerformanceSuite
#endif

/// Per-foreground-session app-rendering live span — start, per-chunk update, finalise. Split so a
/// backend reading the caller-injected auto-termination attribute at `onStart` can close it on an
/// unclean exit. Sibling file to keep `OTelSpanEmitter` under SwiftLint's length limit.
extension OTelSpanEmitter {

    /// Opens the session live span. `shouldEmit` and the attribute provider are deferred to
    /// finalize (their context needs `sessionEndedAt`); the auto-termination attribute is stamped at start.
    func startAppRenderingLiveSpan(
        sessionStartedAt: Date
    ) -> any OpenTelemetryApi.Span {
        return startLiveSpanRaw(
            spanName: prefixed(OTelSemanticConventions.SpanName.appRendering),
            startTime: sessionStartedAt,
            attributes: [:]
        )
    }

    /// Re-applies cumulative rendering counters on every chunk so an auto-terminated span
    /// (ended by the backend without our code running) ships with the latest snapshot.
    func applyRenderingAttributes(
        span: any OpenTelemetryApi.Span,
        metrics: RenderingMetrics
    ) {
        for (key, value) in renderingAttributes(metrics: metrics) {
            span.setAttribute(key: key, value: value)
        }
    }

    /// Clean-path finalize: computes `app.session.duration.ms`, runs `shouldEmit` + host
    /// `attributeProvider` against the complete context, ends at `sessionEndedAt`.
    func finalizeAppRenderingLiveSpan(
        span: any OpenTelemetryApi.Span,
        metrics: RenderingMetrics,
        sessionStartedAt: Date,
        sessionEndedAt: Date
    ) {
        // Re-apply counters in case the final chunk arrived between the per-chunk
        // lock release and the finalize lock acquire.
        applyRenderingAttributes(span: span, metrics: metrics)

        var sdkAttributes: [String: AttributeValue] = [:]
        let durationSeconds = sessionEndedAt.timeIntervalSince(sessionStartedAt)
        let durationMs = Int((durationSeconds * 1000).rounded())
        sdkAttributes[OTelSemanticConventions.Attribute.appSessionDurationMs] = .int(durationMs)

        finalizeLiveSpan(
            span: span,
            endTime: sessionEndedAt,
            finalAttributes: SDKAttributeSet(
                values: sdkAttributes,
                reservedKeys: OTelSDKKeys.appRendering
            ),
            context: .appRendering(AppRenderingContext(
                sessionStartedAt: sessionStartedAt,
                sessionEndedAt: sessionEndedAt
            ))
        )
    }
}
