//
//  OTelSpanEmitter.swift
//  PerformanceSuiteOTel
//
//  Created by Ahmed Nafei on 30/04/2026.
//

import Foundation
import OpenTelemetryApi
import UIKit

// In SwiftPM we import the sibling `PerformanceSuite` module; in CocoaPods all
// subspec sources live in one module so this import would be a self-reference.
#if canImport(PerformanceSuiteOTel)
import PerformanceSuite
#endif

/// Internal helper that builds and finalises one OTel span per metric received
/// from PerformanceSuite. Each public method on ``OTelInstrumenter`` delegates
/// to one method here, keeping the instrumenter focused on protocol conformance
/// and identifier conversion.
///
/// Each per-signal `emit*Span(...)` method shapes the SDK attribute dictionary
/// for its signal, then hands off to the shared `emitSpan` pipeline, which
/// applies the `shouldEmit` gate, merges host attributes, and builds the span.
///
/// Behaviour:
///
/// * The `TracerProvider` is **lazily resolved at first emission**, not at
///   construction — PerformanceSuite typically initialises before the OTel SDK
///   registers the global provider.
/// * `setNoParent()` is called on every span. PerformanceSuite metrics are
///   leaf measurements with no caller-scoped active span.
/// * Span timing is supplied by the per-signal caller as an explicit
///   `(startTime, endTime)` pair. Most callers compute it from a duration via
///   `nowWindow(durationInterval:)`. The hang emitter passes
///   `(info.detectedAt, info.detectedAt + info.duration)` when `detectedAt` is
///   non-nil; the per-session app-rendering emitter passes the
///   `didBecomeActive` / `didEnterBackground` timestamps.
/// * Attributes are merged through the shared
///   ``mergeOTelAttributes(sdkSet:sdkSetKeys:provider:context:)`` helper.
/// * The optional `shouldEmit` closure is invoked on every emission before
///   the merge call. Returning `false` short-circuits the emission — no span
///   is built, no provider attributes are evaluated, no tracer is resolved.
final class OTelSpanEmitter {

    private let tracerProvider: (any TracerProvider)?
    private let instrumentationName: String
    private let instrumentationVersion: String?
    private let spanNamePrefix: String?
    private let attributeProvider: OTelAttributeProvider?
    private let shouldEmit: ((PerformanceSuiteSignalContext) -> Bool)?
    private let now: () -> Date

    init(
        tracerProvider: (any TracerProvider)?,
        instrumentationName: String,
        instrumentationVersion: String?,
        spanNamePrefix: String? = nil,
        attributeProvider: OTelAttributeProvider? = nil,
        shouldEmit: ((PerformanceSuiteSignalContext) -> Bool)? = nil,
        now: @escaping () -> Date = Date.init
    ) {
        self.tracerProvider = tracerProvider
        self.instrumentationName = instrumentationName
        self.instrumentationVersion = instrumentationVersion
        self.spanNamePrefix = spanNamePrefix
        self.attributeProvider = attributeProvider
        self.shouldEmit = shouldEmit
        self.now = now
    }

    func prefixed(_ name: String) -> String {
        guard let spanNamePrefix, !spanNamePrefix.isEmpty else { return name }
        return "\(spanNamePrefix).\(name)"
    }

    private func tracer() -> any Tracer {
        let provider = tracerProvider ?? OpenTelemetry.instance.tracerProvider
        return provider.get(
            instrumentationName: instrumentationName,
            instrumentationVersion: instrumentationVersion
        )
    }

    /// Builds an `(endTime = now, startTime = endTime - durationInterval)`
    /// window. Used by signal types whose payload carries a duration but no
    /// explicit start timestamp.
    private func nowWindow(durationInterval: TimeInterval) -> (start: Date, end: Date) {
        let endTime = now()
        let startTime = endTime.addingTimeInterval(-durationInterval)
        return (startTime, endTime)
    }

    // MARK: - Shared span pipeline

    /// Owns the complete gate + merge + builder + apply + finalise pipeline
    /// for every span emission. Per-signal methods shape `attributes` (the
    /// SDK-set surface plus its reserved-key set) and the `(startTime, endTime)`
    /// pair, then delegate the rest here.
    ///
    /// Passing `startTime == endTime` produces a zero-length point span — used
    /// by ``emitWatchdogTerminationSpan(data:)`` since watchdog terminations
    /// are detected on the next launch with no recoverable duration.
    func emitSpan(
        spanName: String,
        startTime: Date,
        endTime: Date,
        attributes: SDKAttributeSet,
        context: PerformanceSuiteSignalContext
    ) {
        if let shouldEmit, !shouldEmit(context) { return }

        let merged = mergeOTelAttributes(
            sdkSet: attributes.values,
            sdkSetKeys: attributes.reservedKeys,
            provider: attributeProvider,
            context: context
        )

        let builder = tracer()
            .spanBuilder(spanName: spanName)
            .setStartTime(time: startTime)
            .setNoParent()
            .setSpanKind(spanKind: .internal)
        for (key, value) in merged {
            builder.setAttribute(key: key, value: value)
        }

        let span = builder.startSpan()
        span.end(time: endTime)
    }

    // MARK: - Startup

    func emitStartupSpan(data: StartupTimeData) {
        let attrs = OTelSemanticConventions.Attribute.self
        var sdkAttributes: [String: AttributeValue] = [:]
        if let ms = data.totalTime.milliseconds {
            sdkAttributes[attrs.startupTotalTimeMs] = .int(ms)
        }
        if let ms = data.mainTime?.milliseconds {
            sdkAttributes[attrs.startupMainTimeMs] = .int(ms)
        }
        if let ms = data.preMainTime?.milliseconds {
            sdkAttributes[attrs.startupPremainTimeMs] = .int(ms)
        }
        sdkAttributes[attrs.startupPrewarmed] = .bool(data.appStartInfo.appStartedWithPrewarming)

        let window = nowWindow(durationInterval: data.totalTime.timeInterval ?? 0)
        emitSpan(
            spanName: prefixed(OTelSemanticConventions.SpanName.appStartup),
            startTime: window.start,
            endTime: window.end,
            attributes: SDKAttributeSet(values: sdkAttributes, reservedKeys: OTelSDKKeys.startup),
            context: .startup(data)
        )
    }

    // MARK: - Screen TTI

    func emitScreenTTISpan(screenName: String, metrics: TTIMetrics) {
        emitTTISpan(
            spanName: prefixed(OTelSemanticConventions.SpanName.screenTTI(screenName)),
            keys: TTIAttributeKeys(
                nameKey: OTelSemanticConventions.Attribute.screenName,
                ttiKey: OTelSemanticConventions.Attribute.screenTTIMs,
                ttfrKey: OTelSemanticConventions.Attribute.screenTTFRMs
            ),
            context: .screenTTI(ScreenContext(screenName: screenName)),
            identifier: screenName,
            metrics: metrics
        )
    }

    // MARK: - Fragment TTI

    func emitFragmentTTISpan(fragmentName: String, metrics: TTIMetrics) {
        emitTTISpan(
            spanName: prefixed(OTelSemanticConventions.SpanName.fragmentTTI(fragmentName)),
            keys: TTIAttributeKeys(
                nameKey: OTelSemanticConventions.Attribute.fragmentName,
                ttiKey: OTelSemanticConventions.Attribute.fragmentTTIMs,
                ttfrKey: OTelSemanticConventions.Attribute.fragmentTTFRMs
            ),
            context: .fragmentTTI(FragmentContext(fragmentName: fragmentName)),
            identifier: fragmentName,
            metrics: metrics
        )
    }

    private func emitTTISpan(
        spanName: String,
        keys: TTIAttributeKeys,
        context: PerformanceSuiteSignalContext,
        identifier: String,
        metrics: TTIMetrics
    ) {
        var sdkAttributes: [String: AttributeValue] = [
            keys.nameKey: .string(identifier),
        ]
        if let ms = metrics.tti.milliseconds {
            sdkAttributes[keys.ttiKey] = .int(ms)
        }
        if let ms = metrics.ttfr.milliseconds {
            sdkAttributes[keys.ttfrKey] = .int(ms)
        }
        let window = nowWindow(durationInterval: metrics.tti.timeInterval ?? 0)
        emitSpan(
            spanName: spanName,
            startTime: window.start,
            endTime: window.end,
            attributes: SDKAttributeSet(values: sdkAttributes, reservedKeys: keys.allKeys),
            context: context
        )
    }

    // MARK: - Screen rendering

    func emitScreenRenderingSpan(screenName: String, metrics: RenderingMetrics) {
        var sdkAttributes: [String: AttributeValue] = [
            OTelSemanticConventions.Attribute.screenName: .string(screenName),
        ]
        addRenderingAttributes(to: &sdkAttributes, metrics: metrics)
        let window = nowWindow(durationInterval: metrics.sessionDuration.timeInterval ?? 0)
        emitSpan(
            spanName: prefixed(OTelSemanticConventions.SpanName.screenRendering(screenName)),
            startTime: window.start,
            endTime: window.end,
            attributes: SDKAttributeSet(values: sdkAttributes, reservedKeys: OTelSDKKeys.screenRendering),
            context: .screenRendering(ScreenContext(screenName: screenName))
        )
    }

    // MARK: - Rendering attributes (shared helper)

    func addRenderingAttributes(to attributes: inout [String: AttributeValue], metrics: RenderingMetrics) {
        let attrs = OTelSemanticConventions.Attribute.self
        attributes[attrs.renderingTotalFrames] = .int(metrics.renderedFrames)
        attributes[attrs.renderingDroppedFrames] = .int(metrics.droppedFrames)
        attributes[attrs.renderingSlowFrames] = .int(metrics.slowFrames)
        if let ms = metrics.freezeTime.milliseconds {
            attributes[attrs.renderingFreezeTimeMs] = .int(ms)
        }
        if let ms = metrics.sessionDuration.milliseconds {
            attributes[attrs.renderingSessionDurationMs] = .int(ms)
        }
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

    /// Emits a hang span for a *non-fatal* hang. Constructs a
    /// ``PerformanceSuiteSignalContext/nonFatalHang(_:)`` context so host
    /// enrichment closures pattern-match the fatality at compile time.
    func emitNonFatalHangSpan(info: HangInfo) {
        emitHangSpan(
            info: info,
            type: OTelSemanticConventions.HangType.nonFatal,
            context: .nonFatalHang(info)
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
            context: context
        )
    }

    // MARK: - Watchdog termination

    func emitWatchdogTerminationSpan(data: WatchdogTerminationData) {
        // Watchdog terminations are detected on the *next* launch. There is no
        // meaningful duration to compute — emit a zero-length point span at
        // the moment of detection.
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

    // MARK: - Helper types
    //
    // ``SDKAttributeSet`` and ``TTIAttributeKeys`` live in
    // `OTelSpanEmitter+Helpers.swift`.
}

// We re-use `DispatchTimeInterval.timeInterval` and `DispatchTimeInterval.milliseconds`
// from PerformanceSuite (Sources/Utils/DispatchTimeInterval+Helpers.swift). When those
// helpers return `nil` (for `.never` / unknown cases), the emitter treats the duration
// as zero so spans always have well-formed `startTime <= endTime` timestamps.
