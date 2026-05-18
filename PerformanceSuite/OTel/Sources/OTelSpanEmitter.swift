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
/// for its signal, then hands off to ``emitSpan(spanName:durationInterval:sdkAttributes:sdkSetKeys:context:)``,
/// which owns the whole timing → merge → build → apply → finalise pipeline.
/// Centralising that pipeline removes the boilerplate that would otherwise be
/// duplicated across every signal.
///
/// Design points:
///
/// * The `TracerProvider` is **lazily resolved at first emission**, not at
///   construction. This is essential because PerformanceSuite typically
///   initialises before the OTel SDK (Embrace) registers the global provider —
///   eagerly capturing `OpenTelemetry.instance.tracerProvider` at init time
///   would freeze the no-op `DefaultTracerProvider` and silently drop every
///   span.
/// * `setNoParent()` is called on every span. PerformanceSuite metrics are
///   leaf measurements with no caller-scoped active span; explicitly making
///   them root spans avoids accidental parent linkage to whatever happens to
///   be active on the queue at emit time.
/// * Span timing is computed as `(now - duration, now)` so that backends see
///   wall-clock-aligned spans and a single batch retains causal ordering.
///   Watchdog termination passes `durationInterval: 0` to record a
///   zero-length point span (start == end) — the natural shape for events
///   detected on the next launch with no recoverable duration.
/// * Attributes are merged through the shared
///   ``mergeOTelAttributes(sdkSet:sdkSetKeys:provider:context:)`` helper so
///   the SDK-key guard runs uniformly across spans and log records.
final class OTelSpanEmitter {

    private let tracerProvider: (any TracerProvider)?
    private let instrumentationName: String
    private let instrumentationVersion: String?
    private let spanNamePrefix: String?
    private let attributeProvider: OTelAttributeProvider?
    private let now: () -> Date

    init(
        tracerProvider: (any TracerProvider)?,
        instrumentationName: String,
        instrumentationVersion: String?,
        spanNamePrefix: String? = nil,
        attributeProvider: OTelAttributeProvider? = nil,
        now: @escaping () -> Date = Date.init
    ) {
        self.tracerProvider = tracerProvider
        self.instrumentationName = instrumentationName
        self.instrumentationVersion = instrumentationVersion
        self.spanNamePrefix = spanNamePrefix
        self.attributeProvider = attributeProvider
        self.now = now
    }

    private func prefixed(_ name: String) -> String {
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

    // MARK: - Shared span pipeline

    /// Owns the complete timing + merge + builder + apply + finalise pipeline
    /// for every span emission. Per-signal methods shape `sdkAttributes` /
    /// `sdkSetKeys` / `context` and delegate the rest here.
    ///
    /// `durationInterval` of 0 produces a zero-length point span (start ==
    /// end) — used by ``emitWatchdogTerminationSpan(data:)``.
    private func emitSpan(
        spanName: String,
        durationInterval: TimeInterval,
        sdkAttributes: [String: AttributeValue],
        sdkSetKeys: Set<String>,
        context: PerformanceSuiteSignalContext
    ) {
        let endTime = now()
        let startTime = endTime.addingTimeInterval(-durationInterval)

        let merged = mergeOTelAttributes(
            sdkSet: sdkAttributes,
            sdkSetKeys: sdkSetKeys,
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
        addOTelDeviceAttributes(to: &sdkAttributes)

        emitSpan(
            spanName: prefixed(OTelSemanticConventions.SpanName.appStartup),
            durationInterval: data.totalTime.timeInterval ?? 0,
            sdkAttributes: sdkAttributes,
            sdkSetKeys: OTelSDKKeys.startup,
            context: .startup(StartupContext())
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
        emitSpan(
            spanName: spanName,
            durationInterval: metrics.tti.timeInterval ?? 0,
            sdkAttributes: sdkAttributes,
            sdkSetKeys: keys.allKeys,
            context: context
        )
    }

    // MARK: - Screen rendering

    func emitScreenRenderingSpan(screenName: String, metrics: RenderingMetrics) {
        var sdkAttributes: [String: AttributeValue] = [
            OTelSemanticConventions.Attribute.screenName: .string(screenName),
        ]
        addRenderingAttributes(to: &sdkAttributes, metrics: metrics)
        emitSpan(
            spanName: prefixed(OTelSemanticConventions.SpanName.screenRendering(screenName)),
            durationInterval: metrics.sessionDuration.timeInterval ?? 0,
            sdkAttributes: sdkAttributes,
            sdkSetKeys: OTelSDKKeys.screenRendering,
            context: .screenRendering(ScreenContext(screenName: screenName))
        )
    }

    // MARK: - App rendering

    func emitAppRenderingSpan(metrics: RenderingMetrics) {
        var sdkAttributes: [String: AttributeValue] = [:]
        addRenderingAttributes(to: &sdkAttributes, metrics: metrics)
        emitSpan(
            spanName: prefixed(OTelSemanticConventions.SpanName.appRendering),
            durationInterval: metrics.sessionDuration.timeInterval ?? 0,
            sdkAttributes: sdkAttributes,
            sdkSetKeys: OTelSDKKeys.appRendering,
            context: .appRendering(AppRenderingContext())
        )
    }

    private func addRenderingAttributes(to attributes: inout [String: AttributeValue], metrics: RenderingMetrics) {
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
        emitSpan(
            spanName: prefixed(OTelSemanticConventions.SpanName.appHang),
            durationInterval: info.duration.timeInterval ?? 0,
            sdkAttributes: sdkAttributes,
            sdkSetKeys: OTelSDKKeys.hang,
            context: context
        )
    }

    // MARK: - Watchdog termination

    func emitWatchdogTerminationSpan(data: WatchdogTerminationData) {
        // Watchdog terminations are detected on the *next* launch. There is no
        // meaningful duration to compute — `durationInterval: 0` records a
        // zero-length point span at the moment of detection.
        let attrs = OTelSemanticConventions.Attribute.self
        var sdkAttributes: [String: AttributeValue] = [
            attrs.appState: .string(otelAppStateString(from: data.applicationState)),
            attrs.deviceRamMb: .int(otelPhysicalMemoryMb()),
        ]
        if let warnings = data.memoryWarnings {
            sdkAttributes[attrs.memoryWarningsCount] = .int(warnings)
        }
        addOTelDeviceAttributes(to: &sdkAttributes)
        emitSpan(
            spanName: prefixed(OTelSemanticConventions.SpanName.appWatchdogTermination),
            durationInterval: 0,
            sdkAttributes: sdkAttributes,
            sdkSetKeys: OTelSDKKeys.watchdogTermination,
            context: .watchdogTermination(data)
        )
    }

    // MARK: - Helper types

    /// Bundles the three attribute keys that vary between screen TTI and
    /// fragment TTI emission, plus exposes them as a `Set<String>` for the
    /// merge guard. Keeps `emitTTISpan(...)` under SwiftLint's 5-parameter
    /// limit and makes the call sites self-documenting.
    private struct TTIAttributeKeys {
        let nameKey: String
        let ttiKey: String
        let ttfrKey: String

        var allKeys: Set<String> { [nameKey, ttiKey, ttfrKey] }
    }
}

// We re-use `DispatchTimeInterval.timeInterval` and `DispatchTimeInterval.milliseconds`
// from PerformanceSuite (Sources/Utils/DispatchTimeInterval+Helpers.swift). When those
// helpers return `nil` (for `.never` / unknown cases), the emitter treats the duration
// as zero so spans always have well-formed `startTime <= endTime` timestamps.
