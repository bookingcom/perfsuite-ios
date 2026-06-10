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

/// Per-foreground-session app-rendering emission. Lives in a sibling file to
/// keep ``OTelSpanEmitter`` under SwiftLint's `file_length` limit.
extension OTelSpanEmitter {

    /// Emits one span per app-foreground session, with the rendering counters
    /// summed across all `appRenderingMetricsReceived` chunks that arrived
    /// between `sessionStartedAt` (`UIApplication.didBecomeActiveNotification`)
    /// and `sessionEndedAt` (`UIApplication.didEnterBackgroundNotification`).
    /// Called by ``AppRenderingSessionAccumulator``.
    ///
    /// The span carries `app.session.duration.ms` equal to the wall-clock
    /// `sessionEndedAt - sessionStartedAt`, alongside the standard rendering
    /// counters (whose `rendering.session_duration.ms` is the sum of measured
    /// frame durations and may differ slightly).
    func emitAppSessionRenderingSpan(
        metrics: RenderingMetrics,
        sessionStartedAt: Date,
        sessionEndedAt: Date
    ) {
        var sdkAttributes: [String: AttributeValue] = [:]
        addRenderingAttributes(to: &sdkAttributes, metrics: metrics)
        let durationSeconds = sessionEndedAt.timeIntervalSince(sessionStartedAt)
        let durationMs = Int((durationSeconds * 1000).rounded())
        sdkAttributes[OTelSemanticConventions.Attribute.appSessionDurationMs] = .int(durationMs)

        emitSpan(
            spanName: prefixed(OTelSemanticConventions.SpanName.appRendering),
            startTime: sessionStartedAt,
            endTime: sessionEndedAt,
            attributes: SDKAttributeSet(values: sdkAttributes, reservedKeys: OTelSDKKeys.appRendering),
            context: .appRendering(AppRenderingContext(
                sessionStartedAt: sessionStartedAt,
                sessionEndedAt: sessionEndedAt
            ))
        )
    }
}
