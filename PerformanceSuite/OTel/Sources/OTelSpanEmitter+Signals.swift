//
//  OTelSpanEmitter+Signals.swift
//  PerformanceSuiteOTel
//

import Foundation
import OpenTelemetryApi

#if canImport(PerformanceSuiteOTel)
import PerformanceSuite
#endif

/// Post-facto span emitters for ``OTelSpanEmitter`` (fatal hang, watchdog termination) plus the
/// shared rendering-attribute helper. Live signals build their spans via `startLiveSpan` /
/// `finalizeLiveSpan`; only signals detected after the fact go through `emitSpan` here.
extension OTelSpanEmitter {

    // MARK: - Rendering attributes (shared helper)

    func renderingAttributes(metrics: RenderingMetrics) -> [String: AttributeValue] {
        let attrs = OTelSemanticConventions.Attribute.self
        var values: [String: AttributeValue] = [
            attrs.renderingTotalFrames: .int(metrics.renderedFrames),
            attrs.renderingDroppedFrames: .int(metrics.droppedFrames),
            attrs.renderingSlowFrames: .int(metrics.slowFrames),
        ]
        if let ms = metrics.freezeTime.milliseconds {
            values[attrs.renderingFreezeTimeMs] = .int(ms)
        }
        if let ms = metrics.sessionDuration.milliseconds {
            values[attrs.renderingSessionDurationMs] = .int(ms)
        }
        return values
    }

    // MARK: - Hangs

    /// Emits a hang span for a *fatal* hang. Constructs a
    /// ``PerformanceSuiteSignalContext/fatalHang(_:)`` context so host
    /// enrichment closures pattern-match the fatality at compile time.
    func emitFatalHangSpan(info: HangInfo) {
        emitHangSpan(
            info: info,
            type: OTelSemanticConventions.HangType.fatal,
            context: .fatalHang(info)
        )
    }

    private func emitHangSpan(
        info: HangInfo,
        type: String,
        context: PerformanceSuiteSignalContext
    ) {
        let attrs = OTelSemanticConventions.Attribute.self
        var sdkAttributes: [String: AttributeValue] = [
            attrs.hangType: .string(type),
            attrs.hangDuringStartup: .bool(info.duringStartup),
        ]
        if let ms = info.duration.milliseconds {
            sdkAttributes[attrs.hangDurationMs] = .int(ms)
        }
        if let topScreen = info.appRuntimeInfo.openedScreens.last {
            sdkAttributes[attrs.hangTopScreen] = .string(topScreen)
        }
        if let sessionId = info.sessionId {
            sdkAttributes[attrs.appSessionId] = .string(sessionId)
        }

        // Anchor the span window on `info.detectedAt` when available; fall
        // back to `now() - duration` when nil.
        let durationInterval = info.duration.timeInterval ?? 0
        let startTime: Date
        let endTime: Date
        if let detectedAt = info.detectedAt {
            startTime = detectedAt
            endTime = detectedAt.addingTimeInterval(durationInterval)
        } else {
            let window = nowWindow(durationInterval: durationInterval)
            startTime = window.start
            endTime = window.end
        }

        emitSpan(
            spanName: prefixed(OTelSemanticConventions.SpanName.appHang),
            startTime: startTime,
            endTime: endTime,
            attributes: SDKAttributeSet(values: sdkAttributes, reservedKeys: OTelSDKKeys.hang),
            context: context,
            // Fatal hangs are detected on the NEXT launch, so the span is created in session N+1.
            // Override `session.id` (post-startSpan) with the session the hang happened in so the
            // backend buckets it correctly instead of attributing it to the launch that reported it.
            sessionIdOverride: info.sessionId
        )
    }

    // MARK: - Watchdog termination

    func emitWatchdogTerminationSpan(data: WatchdogTerminationData) {
        let attrs = OTelSemanticConventions.Attribute.self
        var sdkAttributes: [String: AttributeValue] = [:]
        if let warnings = data.memoryWarnings {
            sdkAttributes[attrs.memoryWarningsCount] = .int(warnings)
        }
        let timestamp = now()
        emitSpan(
            spanName: prefixed(OTelSemanticConventions.SpanName.appWatchdogTermination),
            startTime: timestamp,
            endTime: timestamp,
            attributes: SDKAttributeSet(values: sdkAttributes, reservedKeys: OTelSDKKeys.watchdogTermination),
            context: .watchdogTermination(data)
        )
    }

}
