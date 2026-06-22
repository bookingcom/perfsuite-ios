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
/// Live signals open a span via `startLiveSpan` / `startLiveSpanRaw` and close it
/// with `finalizeLiveSpan`. Inherently post-facto signals (fatal hang, watchdog)
/// emit a completed span through the shared `emitSpan` pipeline.
///
/// Behaviour:
///
/// * The `TracerProvider` is **lazily resolved at first emission**, not at
///   construction — PerformanceSuite typically initialises before the OTel SDK
///   registers the global provider.
/// * `setNoParent()` is called on every span. PerformanceSuite metrics are
///   leaf measurements with no caller-scoped active span.
/// * Timing is an explicit (startTime, endTime) pair — anchored on a payload
///   timestamp (process start, `info.detectedAt`, `metrics.sessionStarted`) or
///   duration-derived via `nowWindow(durationInterval:)`.
/// * Attributes are merged through ``mergeOTelAttributes(sdkSet:sdkSetKeys:provider:context:)``.
/// * `shouldEmit` gates `startLiveSpan` and `emitSpan` (rejection drops the span);
///   for raw live spans it is deferred to `finalizeLiveSpan`, which closes a
///   rejected span with `Status.error("shouldEmit_rejected")`.
final class OTelSpanEmitter {

    private let tracerProvider: (any TracerProvider)?
    private let instrumentationName: String
    private let instrumentationVersion: String?
    private let spanNamePrefix: String?
    private let attributeProvider: OTelAttributeProvider?
    private let shouldEmit: ((PerformanceSuiteSignalContext) -> Bool)?
    /// Optional `(key, value)` stamped on every live span at start (never on completed spans), for
    /// a backend that reads it at `onStart` to end the span on an unclean exit. Reserved at the
    /// merge sites so a host `attributeProvider` can't overwrite it. `nil` = vendor-neutral default.
    private let autoTerminationAttribute: (key: String, value: String)?
    // Internal so the per-signal emitters in OTelSpanEmitter+Signals.swift reach them.
    let now: () -> Date

    init(
        tracerProvider: (any TracerProvider)?,
        instrumentationName: String,
        instrumentationVersion: String?,
        spanNamePrefix: String? = nil,
        attributeProvider: OTelAttributeProvider? = nil,
        shouldEmit: ((PerformanceSuiteSignalContext) -> Bool)? = nil,
        autoTerminationAttribute: (key: String, value: String)? = nil,
        now: @escaping () -> Date = Date.init
    ) {
        self.tracerProvider = tracerProvider
        self.instrumentationName = instrumentationName
        self.instrumentationVersion = instrumentationVersion
        self.spanNamePrefix = spanNamePrefix
        self.attributeProvider = attributeProvider
        self.shouldEmit = shouldEmit
        self.autoTerminationAttribute = autoTerminationAttribute
        self.now = now
    }

    /// `base` widened with the auto-termination key (when set) so a host `attributeProvider`
    /// can't overwrite it.
    private func reservedKeys(_ base: Set<String>) -> Set<String> {
        guard let key = autoTerminationAttribute?.key else { return base }
        return base.union([key])
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
    func nowWindow(durationInterval: TimeInterval) -> (start: Date, end: Date) {
        let endTime = now()
        let startTime = endTime.addingTimeInterval(-durationInterval)
        return (startTime, endTime)
    }

    // MARK: - Completed span pipeline

    /// Builds and ends a completed span in one shot (gate + merge + build + end) for post-facto
    /// signals. Per-signal methods shape `attributes` and the `(startTime, endTime)` pair.
    ///
    /// Passing `startTime == endTime` produces a zero-length point span — used
    /// by ``emitWatchdogTerminationSpan(data:)`` since watchdog terminations
    /// are detected on the next launch with no recoverable duration.
    func emitSpan(
        spanName: String,
        startTime: Date,
        endTime: Date,
        attributes: SDKAttributeSet,
        context: PerformanceSuiteSignalContext,
        sessionIdOverride: String? = nil
    ) {
        if let shouldEmit, !shouldEmit(context) { return }

        let merged = mergeOTelAttributes(
            sdkSet: attributes.values,
            sdkSetKeys: attributes.reservedKeys,
            provider: attributeProvider,
            context: context
        )

        let span = makeBuilder(spanName: spanName, startTime: startTime, attributes: merged).startSpan()
        // A backend session processor (e.g. Embrace's `EmbraceSpanProcessor.onStart`) stamps the
        // session-bucketing key = the CURRENT session on every span at start, overwriting anything set
        // pre-start. A post-facto signal (a fatal hang detected on the NEXT launch) must be attributed
        // to the session it actually happened in — so set the key AFTER `startSpan` so it survives the
        // onStart overwrite and lands on the completed span exported at onEnd (the backend buckets by
        // this attribute). The key is the generic OTel `session.id` (== Embrace's `SpanSemantics
        // .keySessionId`), so it's hardcoded rather than injected.
        if let sessionIdOverride {
            span.setAttribute(
                key: OTelSemanticConventions.Attribute.sessionId,
                value: .string(sessionIdOverride))
        }
        span.end(time: endTime)
    }

    // MARK: - Live span pipeline

    /// Builder prelude shared by `emitSpan` (completed) and `makeStartedSpan` (live):
    /// `setNoParent`, `.internal` kind, given start time, attributes set pre-start.
    private func makeBuilder(
        spanName: String,
        startTime: Date,
        attributes: [String: AttributeValue]
    ) -> any SpanBuilder {
        let builder = tracer()
            .spanBuilder(spanName: spanName)
            .setStartTime(time: startTime)
            .setNoParent()
            .setSpanKind(spanKind: .internal)
        for (key, value) in attributes {
            builder.setAttribute(key: key, value: value)
        }
        return builder
    }

    /// Live-span builder: adds the optional auto-termination stamp (live spans only — completed
    /// spans go through `emitSpan`) so it's present at `startSpan()` for an onStart-based backend.
    /// `autoTerminate: false` opts a signal out of the stamp — used by hangs, whose unclean-exit
    /// case already has an authoritative next-launch record, so an auto-terminated orphan would
    /// just double-count it.
    private func makeStartedSpan(
        spanName: String,
        startTime: Date,
        attributes: [String: AttributeValue],
        autoTerminate: Bool
    ) -> any OpenTelemetryApi.Span {
        let builder = makeBuilder(spanName: spanName, startTime: startTime, attributes: attributes)
        if autoTerminate, let autoTerminationAttribute {
            builder.setAttribute(key: autoTerminationAttribute.key, value: .string(autoTerminationAttribute.value))
        }
        return builder.startSpan()
    }

    /// Starts a live span for signals with fully-known context at start time (screen
    /// TTI, fragment TTI, screen rendering). Evaluates `shouldEmit` and merges host
    /// attributes here; returns `nil` when the gate rejects.
    func startLiveSpan(
        spanName: String,
        startTime: Date,
        attributes: SDKAttributeSet,
        context: PerformanceSuiteSignalContext
    ) -> (any OpenTelemetryApi.Span)? {
        if let shouldEmit, !shouldEmit(context) { return nil }
        let merged = mergeOTelAttributes(
            sdkSet: attributes.values,
            sdkSetKeys: reservedKeys(attributes.reservedKeys),
            provider: attributeProvider,
            context: context
        )
        return makeStartedSpan(spanName: spanName, startTime: startTime, attributes: merged, autoTerminate: true)
    }

    /// Starts a live span without `shouldEmit` or host attribute provider (their context
    /// isn't complete yet). The caller MUST reach `finalizeLiveSpan` — which evaluates
    /// `shouldEmit` and closes a rejected span with `Status.error("shouldEmit_rejected")`
    /// so it doesn't leak as a perpetually-open span. Pass `autoTerminate: false` for signals
    /// that have their own post-facto record (hangs) so an unclean exit doesn't double-count.
    func startLiveSpanRaw(
        spanName: String,
        startTime: Date,
        attributes: [String: AttributeValue],
        autoTerminate: Bool = true
    ) -> any OpenTelemetryApi.Span {
        return makeStartedSpan(spanName: spanName, startTime: startTime, attributes: attributes, autoTerminate: autoTerminate)
    }

    /// Finalises a live span: applies final SDK attributes + host attributes against the
    /// now-complete `context` and ends at `endTime`. If `shouldEmit` rejects, ends with
    /// `Status.error("shouldEmit_rejected")` so downstream filters can drop the span.
    /// `finalAttributes.reservedKeys` MUST cover both start-time AND end-time SDK keys.
    func finalizeLiveSpan(
        span: any OpenTelemetryApi.Span,
        endTime: Date,
        finalAttributes: SDKAttributeSet,
        context: PerformanceSuiteSignalContext
    ) {
        if let shouldEmit, !shouldEmit(context) {
            span.status = .error(description: "shouldEmit_rejected")
            span.end(time: endTime)
            return
        }

        let merged = mergeOTelAttributes(
            sdkSet: finalAttributes.values,
            sdkSetKeys: reservedKeys(finalAttributes.reservedKeys),
            provider: attributeProvider,
            context: context
        )
        for (key, value) in merged {
            span.setAttribute(key: key, value: value)
        }
        span.end(time: endTime)
    }

    // MARK: - Helper types
    //
    // ``SDKAttributeSet`` lives in `OTelSpanEmitter+Helpers.swift`.
}
