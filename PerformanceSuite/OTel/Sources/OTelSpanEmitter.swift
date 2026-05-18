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
///   span.
/// * `setNoParent()` is called on every span. PerformanceSuite metrics are
///   leaf measurements with no caller-scoped active span; explicitly making
///   them root spans avoids accidental parent linkage to whatever happens to
///   be active on the queue at emit time.
/// * Span timing is computed as `(now - duration, now)` so that backends see
///   wall-clock-aligned spans and a single batch retains causal ordering.
/// * Attributes are collected into an SDK dict, merged with any host
///   ``OTelAttributeProvider`` output through ``mergeOTelAttributes(sdkSet:sdkSetKeys:provider:context:)``,
///   then applied to the span builder. The merge filters host attributes
///   against per-signal `*SDKKeys` sets so SDK semantic-convention keys can
///   never be overwritten by the host.
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

    // MARK: - Tracer resolution

    private func tracer() -> any Tracer {
        let provider = tracerProvider ?? OpenTelemetry.instance.tracerProvider
        return provider.get(
            instrumentationName: instrumentationName,
            instrumentationVersion: instrumentationVersion
        )
    }

    // MARK: - Builder helpers

    private func makeBuilder(spanName: String, startTime: Date) -> SpanBuilder {
        tracer()
            .spanBuilder(spanName: spanName)
            .setStartTime(time: startTime)
            .setNoParent()
            .setSpanKind(spanKind: .internal)
    }

    private func apply(_ attributes: [String: AttributeValue], to builder: SpanBuilder) {
        for (key, value) in attributes {
            builder.setAttribute(key: key, value: value)
        }
    }

    // MARK: - Startup

    func emitStartupSpan(data: StartupTimeData) {
        let endTime = now()
        let startTime = endTime.addingTimeInterval(-(data.totalTime.timeInterval ?? 0))

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
        addDeviceAttributes(to: &sdkAttributes)

        let merged = mergeOTelAttributes(
            sdkSet: sdkAttributes,
            sdkSetKeys: Self.startupSDKKeys,
            provider: attributeProvider,
            context: .startup(StartupContext())
        )

        let builder = makeBuilder(
            spanName: prefixed(OTelSemanticConventions.SpanName.appStartup),
            startTime: startTime
        )
        apply(merged, to: builder)

        let span = builder.startSpan()
        span.end(time: endTime)
    }

    static let startupSDKKeys: Set<String> = [
        OTelSemanticConventions.Attribute.startupTotalTimeMs,
        OTelSemanticConventions.Attribute.startupMainTimeMs,
        OTelSemanticConventions.Attribute.startupPremainTimeMs,
        OTelSemanticConventions.Attribute.startupPrewarmed,
        OTelSemanticConventions.Attribute.osName,
        OTelSemanticConventions.Attribute.osVersion,
        OTelSemanticConventions.Attribute.deviceModel,
    ]

    // MARK: - Screen TTI

    func emitScreenTTISpan(screenName: String, metrics: TTIMetrics) {
        emitTTISpan(
            spanName: prefixed(OTelSemanticConventions.SpanName.screenTTI(screenName)),
            keys: TTIAttributeKeys(
                nameKey: OTelSemanticConventions.Attribute.screenName,
                ttiKey: OTelSemanticConventions.Attribute.screenTTIMs,
                ttfrKey: OTelSemanticConventions.Attribute.screenTTFRMs
            ),
            sdkSetKeys: Self.screenTTISDKKeys,
            context: .screenTTI(ScreenContext(screenName: screenName)),
            identifier: screenName,
            metrics: metrics
        )
    }

    static let screenTTISDKKeys: Set<String> = [
        OTelSemanticConventions.Attribute.screenName,
        OTelSemanticConventions.Attribute.screenTTIMs,
        OTelSemanticConventions.Attribute.screenTTFRMs,
    ]

    // MARK: - Fragment TTI

    func emitFragmentTTISpan(fragmentName: String, metrics: TTIMetrics) {
        emitTTISpan(
            spanName: prefixed(OTelSemanticConventions.SpanName.fragmentTTI(fragmentName)),
            keys: TTIAttributeKeys(
                nameKey: OTelSemanticConventions.Attribute.fragmentName,
                ttiKey: OTelSemanticConventions.Attribute.fragmentTTIMs,
                ttfrKey: OTelSemanticConventions.Attribute.fragmentTTFRMs
            ),
            sdkSetKeys: Self.fragmentTTISDKKeys,
            context: .fragmentTTI(FragmentContext(fragmentName: fragmentName)),
            identifier: fragmentName,
            metrics: metrics
        )
    }

    static let fragmentTTISDKKeys: Set<String> = [
        OTelSemanticConventions.Attribute.fragmentName,
        OTelSemanticConventions.Attribute.fragmentTTIMs,
        OTelSemanticConventions.Attribute.fragmentTTFRMs,
    ]

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
        sdkSetKeys: Set<String>,
        context: PerformanceSuiteSignalContext,
        identifier: String,
        metrics: TTIMetrics
    ) {
        let endTime = now()
        let startTime = endTime.addingTimeInterval(-(metrics.tti.timeInterval ?? 0))

        var sdkAttributes: [String: AttributeValue] = [
            keys.nameKey: .string(identifier),
        ]
        if let ms = metrics.tti.milliseconds {
            sdkAttributes[keys.ttiKey] = .int(ms)
        }
        if let ms = metrics.ttfr.milliseconds {
            sdkAttributes[keys.ttfrKey] = .int(ms)
        }

        let merged = mergeOTelAttributes(
            sdkSet: sdkAttributes,
            sdkSetKeys: sdkSetKeys,
            provider: attributeProvider,
            context: context
        )

        let builder = makeBuilder(spanName: spanName, startTime: startTime)
        apply(merged, to: builder)

        let span = builder.startSpan()
        span.end(time: endTime)
    }

    // MARK: - Screen rendering

    func emitScreenRenderingSpan(screenName: String, metrics: RenderingMetrics) {
        let endTime = now()
        let startTime = endTime.addingTimeInterval(-(metrics.sessionDuration.timeInterval ?? 0))

        var sdkAttributes: [String: AttributeValue] = [
            OTelSemanticConventions.Attribute.screenName: .string(screenName),
        ]
        addRenderingAttributes(to: &sdkAttributes, metrics: metrics)

        let merged = mergeOTelAttributes(
            sdkSet: sdkAttributes,
            sdkSetKeys: Self.screenRenderingSDKKeys,
            provider: attributeProvider,
            context: .screenRendering(ScreenContext(screenName: screenName))
        )

        let builder = makeBuilder(
            spanName: prefixed(OTelSemanticConventions.SpanName.screenRendering(screenName)),
            startTime: startTime
        )
        apply(merged, to: builder)

        let span = builder.startSpan()
        span.end(time: endTime)
    }

    static let screenRenderingSDKKeys: Set<String> = [
        OTelSemanticConventions.Attribute.screenName,
        OTelSemanticConventions.Attribute.renderingTotalFrames,
        OTelSemanticConventions.Attribute.renderingDroppedFrames,
        OTelSemanticConventions.Attribute.renderingSlowFrames,
        OTelSemanticConventions.Attribute.renderingFreezeTimeMs,
        OTelSemanticConventions.Attribute.renderingSessionDurationMs,
    ]

    // MARK: - App rendering

    func emitAppRenderingSpan(metrics: RenderingMetrics) {
        let endTime = now()
        let startTime = endTime.addingTimeInterval(-(metrics.sessionDuration.timeInterval ?? 0))

        var sdkAttributes: [String: AttributeValue] = [:]
        addRenderingAttributes(to: &sdkAttributes, metrics: metrics)

        let merged = mergeOTelAttributes(
            sdkSet: sdkAttributes,
            sdkSetKeys: Self.appRenderingSDKKeys,
            provider: attributeProvider,
            context: .appRendering(AppRenderingContext())
        )

        let builder = makeBuilder(
            spanName: prefixed(OTelSemanticConventions.SpanName.appRendering),
            startTime: startTime
        )
        apply(merged, to: builder)

        let span = builder.startSpan()
        span.end(time: endTime)
    }

    static let appRenderingSDKKeys: Set<String> = [
        OTelSemanticConventions.Attribute.renderingTotalFrames,
        OTelSemanticConventions.Attribute.renderingDroppedFrames,
        OTelSemanticConventions.Attribute.renderingSlowFrames,
        OTelSemanticConventions.Attribute.renderingFreezeTimeMs,
        OTelSemanticConventions.Attribute.renderingSessionDurationMs,
    ]

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
        let endTime = now()
        let startTime = endTime.addingTimeInterval(-(info.duration.timeInterval ?? 0))

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

        let merged = mergeOTelAttributes(
            sdkSet: sdkAttributes,
            sdkSetKeys: Self.hangSDKKeys,
            provider: attributeProvider,
            context: context
        )

        let builder = makeBuilder(
            spanName: prefixed(OTelSemanticConventions.SpanName.appHang),
            startTime: startTime
        )
        apply(merged, to: builder)

        let span = builder.startSpan()
        span.end(time: endTime)
    }

    static let hangSDKKeys: Set<String> = [
        OTelSemanticConventions.Attribute.hangType,
        OTelSemanticConventions.Attribute.hangDuringStartup,
        OTelSemanticConventions.Attribute.hangDurationMs,
        OTelSemanticConventions.Attribute.hangTopScreen,
    ]

    // MARK: - Watchdog termination

    func emitWatchdogTerminationSpan(data: WatchdogTerminationData) {
        // Watchdog terminations are detected on the *next* launch. There is no
        // meaningful duration to compute — record as a zero-length point span at
        // the moment of detection.
        let pointInTime = now()

        let attrs = OTelSemanticConventions.Attribute.self
        var sdkAttributes: [String: AttributeValue] = [
            attrs.appState: .string(stringFrom(applicationState: data.applicationState)),
            attrs.deviceRamMb: .int(Int(physicalMemoryMb())),
        ]
        if let warnings = data.memoryWarnings {
            sdkAttributes[attrs.memoryWarningsCount] = .int(warnings)
        }
        addDeviceAttributes(to: &sdkAttributes)

        let merged = mergeOTelAttributes(
            sdkSet: sdkAttributes,
            sdkSetKeys: Self.watchdogTerminationSDKKeys,
            provider: attributeProvider,
            context: .watchdogTermination(data)
        )

        let builder = makeBuilder(
            spanName: prefixed(OTelSemanticConventions.SpanName.appWatchdogTermination),
            startTime: pointInTime
        )
        apply(merged, to: builder)

        let span = builder.startSpan()
        span.end(time: pointInTime)
    }

    static let watchdogTerminationSDKKeys: Set<String> = [
        OTelSemanticConventions.Attribute.appState,
        OTelSemanticConventions.Attribute.memoryWarningsCount,
        OTelSemanticConventions.Attribute.deviceRamMb,
        OTelSemanticConventions.Attribute.osName,
        OTelSemanticConventions.Attribute.osVersion,
        OTelSemanticConventions.Attribute.deviceModel,
    ]

    // MARK: - Device / OS attributes

    private func addDeviceAttributes(to attributes: inout [String: AttributeValue]) {
        let attrs = OTelSemanticConventions.Attribute.self
        attributes[attrs.osName] = .string(OTelSemanticConventions.osNameValue)
        attributes[attrs.osVersion] = .string(UIDevice.current.systemVersion)
        attributes[attrs.deviceModel] = .string(deviceModelCode())
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
