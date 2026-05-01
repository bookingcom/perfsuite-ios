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
/// Design points:
///
/// * The `TracerProvider` is **lazily resolved at first emission**, not at
///   construction. This is essential because PerformanceSuite typically
///   initialises before the OTel SDK (Embrace) registers the global provider —
///   eagerly capturing `OpenTelemetry.instance.tracerProvider` at init time
///   would freeze the no-op `DefaultTracerProvider` and silently drop every
///   span. See RFC §9 for the initialization-ordering analysis.
/// * `setNoParent()` is called on every span. PerformanceSuite metrics are
///   leaf measurements with no caller-scoped active span; explicitly making
///   them root spans avoids accidental parent linkage to whatever happens to
///   be active on the queue at emit time.
/// * Span timing is computed as `(now - duration, now)` so that backends see
///   wall-clock-aligned spans and a single batch retains causal ordering.
final class OTelSpanEmitter {

    private let tracerProvider: (any TracerProvider)?
    private let instrumentationName: String
    private let instrumentationVersion: String?
    private let spanNamePrefix: String?
    private let now: () -> Date

    init(
        tracerProvider: (any TracerProvider)?,
        instrumentationName: String,
        instrumentationVersion: String?,
        spanNamePrefix: String? = nil,
        now: @escaping () -> Date = Date.init
    ) {
        self.tracerProvider = tracerProvider
        self.instrumentationName = instrumentationName
        self.instrumentationVersion = instrumentationVersion
        self.spanNamePrefix = spanNamePrefix
        self.now = now
    }

    private func prefixed(_ name: String) -> String {
        guard let spanNamePrefix, !spanNamePrefix.isEmpty else { return name }
        return "\(spanNamePrefix).\(name)"
    }

    // MARK: - Tracer resolution

    private func tracer() -> any Tracer {
        let provider = tracerProvider ?? OpenTelemetry.instance.tracerProvider
        return provider.get(
            instrumentationName: instrumentationName,
            instrumentationVersion: instrumentationVersion
        )
    }

    // MARK: - Startup

    func emitStartupSpan(data: StartupTimeData) {
        let endTime = now()
        let startTime = endTime.addingTimeInterval(-(data.totalTime.timeInterval ?? 0))

        let builder = tracer()
            .spanBuilder(spanName: prefixed(OTelSemanticConventions.SpanName.appStartup))
            .setStartTime(time: startTime)
            .setNoParent()
            .setSpanKind(spanKind: .internal)

        let attrs = OTelSemanticConventions.Attribute.self
        if let ms = data.totalTime.milliseconds {
            builder.setAttribute(key: attrs.startupTotalTimeMs, value: ms)
        }
        if let ms = data.mainTime?.milliseconds {
            builder.setAttribute(key: attrs.startupMainTimeMs, value: ms)
        }
        if let ms = data.preMainTime?.milliseconds {
            builder.setAttribute(key: attrs.startupPremainTimeMs, value: ms)
        }
        builder.setAttribute(key: attrs.startupPrewarmed, value: data.appStartInfo.appStartedWithPrewarming)

        applyDeviceAttributes(to: builder)

        let span = builder.startSpan()
        span.end(time: endTime)
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
            identifier: fragmentName,
            metrics: metrics
        )
    }

    /// Bundles the three attribute keys that vary between screen TTI and
    /// fragment TTI emission. Bundling keeps `emitTTISpan(...)` under
    /// SwiftLint's 5-parameter limit and makes the call sites self-documenting.
    private struct TTIAttributeKeys {
        let nameKey: String
        let ttiKey: String
        let ttfrKey: String
    }

    private func emitTTISpan(
        spanName: String,
        keys: TTIAttributeKeys,
        identifier: String,
        metrics: TTIMetrics
    ) {
        let endTime = now()
        let startTime = endTime.addingTimeInterval(-(metrics.tti.timeInterval ?? 0))

        let builder = tracer()
            .spanBuilder(spanName: spanName)
            .setStartTime(time: startTime)
            .setNoParent()
            .setSpanKind(spanKind: .internal)
            .setAttribute(key: keys.nameKey, value: identifier)

        if let ms = metrics.tti.milliseconds {
            builder.setAttribute(key: keys.ttiKey, value: ms)
        }
        if let ms = metrics.ttfr.milliseconds {
            builder.setAttribute(key: keys.ttfrKey, value: ms)
        }

        let span = builder.startSpan()
        span.end(time: endTime)
    }

    // MARK: - Screen rendering

    func emitScreenRenderingSpan(screenName: String, metrics: RenderingMetrics) {
        let endTime = now()
        let startTime = endTime.addingTimeInterval(-(metrics.sessionDuration.timeInterval ?? 0))

        let builder = tracer()
            .spanBuilder(spanName: prefixed(OTelSemanticConventions.SpanName.screenRendering(screenName)))
            .setStartTime(time: startTime)
            .setNoParent()
            .setSpanKind(spanKind: .internal)
            .setAttribute(key: OTelSemanticConventions.Attribute.screenName, value: screenName)

        applyRenderingAttributes(to: builder, metrics: metrics)

        let span = builder.startSpan()
        span.end(time: endTime)
    }

    // MARK: - App rendering

    func emitAppRenderingSpan(metrics: RenderingMetrics) {
        let endTime = now()
        let startTime = endTime.addingTimeInterval(-(metrics.sessionDuration.timeInterval ?? 0))

        let builder = tracer()
            .spanBuilder(spanName: prefixed(OTelSemanticConventions.SpanName.appRendering))
            .setStartTime(time: startTime)
            .setNoParent()
            .setSpanKind(spanKind: .internal)

        applyRenderingAttributes(to: builder, metrics: metrics)

        let span = builder.startSpan()
        span.end(time: endTime)
    }

    private func applyRenderingAttributes(to builder: SpanBuilder, metrics: RenderingMetrics) {
        let attrs = OTelSemanticConventions.Attribute.self
        builder.setAttribute(key: attrs.renderingTotalFrames, value: metrics.renderedFrames)
        builder.setAttribute(key: attrs.renderingDroppedFrames, value: metrics.droppedFrames)
        builder.setAttribute(key: attrs.renderingSlowFrames, value: metrics.slowFrames)
        if let ms = metrics.freezeTime.milliseconds {
            builder.setAttribute(key: attrs.renderingFreezeTimeMs, value: ms)
        }
        if let ms = metrics.sessionDuration.milliseconds {
            builder.setAttribute(key: attrs.renderingSessionDurationMs, value: ms)
        }
    }

    // MARK: - Hangs

    func emitHangSpan(info: HangInfo, type: String) {
        let endTime = now()
        let startTime = endTime.addingTimeInterval(-(info.duration.timeInterval ?? 0))

        let builder = tracer()
            .spanBuilder(spanName: prefixed(OTelSemanticConventions.SpanName.appHang))
            .setStartTime(time: startTime)
            .setNoParent()
            .setSpanKind(spanKind: .internal)
            .setAttribute(key: OTelSemanticConventions.Attribute.hangType, value: type)
            .setAttribute(key: OTelSemanticConventions.Attribute.hangDuringStartup, value: info.duringStartup)

        if let ms = info.duration.milliseconds {
            builder.setAttribute(key: OTelSemanticConventions.Attribute.hangDurationMs, value: ms)
        }
        if let topScreen = info.appRuntimeInfo.openedScreens.last {
            builder.setAttribute(key: OTelSemanticConventions.Attribute.hangTopScreen, value: topScreen)
        }

        let span = builder.startSpan()
        span.end(time: endTime)
    }

    // MARK: - Watchdog termination

    func emitWatchdogTerminationSpan(data: WatchdogTerminationData) {
        // Watchdog terminations are detected on the *next* launch. There is no
        // meaningful duration to compute — record as a zero-length point span at
        // the moment of detection.
        let pointInTime = now()

        let builder = tracer()
            .spanBuilder(spanName: prefixed(OTelSemanticConventions.SpanName.appWatchdogTermination))
            .setStartTime(time: pointInTime)
            .setNoParent()
            .setSpanKind(spanKind: .internal)

        let attrs = OTelSemanticConventions.Attribute.self
        builder.setAttribute(key: attrs.appState, value: stringFrom(applicationState: data.applicationState))
        if let warnings = data.memoryWarnings {
            builder.setAttribute(key: attrs.memoryWarningsCount, value: warnings)
        }
        builder.setAttribute(key: attrs.deviceRamMb, value: Int(physicalMemoryMb()))

        applyDeviceAttributes(to: builder)

        let span = builder.startSpan()
        span.end(time: pointInTime)
    }

    // MARK: - Device / OS attributes

    private func applyDeviceAttributes(to builder: SpanBuilder) {
        let attrs = OTelSemanticConventions.Attribute.self
        builder.setAttribute(key: attrs.osName, value: OTelSemanticConventions.osNameValue)
        builder.setAttribute(key: attrs.osVersion, value: UIDevice.current.systemVersion)
        builder.setAttribute(key: attrs.deviceModel, value: deviceModelCode())
    }

    /// Hardware model code such as `"iPhone15,3"` (vs. the marketing name
    /// `UIDevice.current.model` returns, which is just `"iPhone"`). Pulled from
    /// `utsname.machine`. Falls back to `UIDevice.current.model` if the syscall
    /// is somehow unavailable.
    private func deviceModelCode() -> String {
        var systemInfo = utsname()
        guard uname(&systemInfo) == 0 else {
            return UIDevice.current.model
        }
        let machineMirror = Mirror(reflecting: systemInfo.machine)
        let identifier = machineMirror.children.reduce(into: "") { acc, element in
            guard let value = element.value as? Int8, value != 0 else { return }
            acc.append(Character(UnicodeScalar(UInt8(value))))
        }
        return identifier.isEmpty ? UIDevice.current.model : identifier
    }

    private func physicalMemoryMb() -> UInt64 {
        ProcessInfo.processInfo.physicalMemory / (1024 * 1024)
    }

    private func stringFrom(applicationState: UIApplication.State?) -> String {
        guard let applicationState else {
            return OTelSemanticConventions.AppState.unknown
        }
        switch applicationState {
        case .active:
            return OTelSemanticConventions.AppState.active
        case .inactive:
            return OTelSemanticConventions.AppState.inactive
        case .background:
            return OTelSemanticConventions.AppState.background
        @unknown default:
            return OTelSemanticConventions.AppState.unknown
        }
    }
}

// We re-use `DispatchTimeInterval.timeInterval` and `DispatchTimeInterval.milliseconds`
// from PerformanceSuite (Sources/Utils/DispatchTimeInterval+Helpers.swift). When those
// helpers return `nil` (for `.never` / unknown cases), the emitter treats the duration
// as zero so spans always have well-formed `startTime <= endTime` timestamps.
