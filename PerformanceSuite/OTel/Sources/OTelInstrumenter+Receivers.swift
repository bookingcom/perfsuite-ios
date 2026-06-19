//
//  OTelInstrumenter+Receivers.swift
//  PerformanceSuiteOTel
//

import Foundation
import OpenTelemetryApi
import UIKit

#if canImport(PerformanceSuiteOTel)
import PerformanceSuite
#endif

/// PerformanceSuite receiver-protocol conformances for ``OTelInstrumenter`` (one method per
/// signal). Split from the main file to keep it under SwiftLint file/type-body length limits.
///
/// OTel is **live-only**: every signal with a start emits a live span. The base `*Received`
/// requirements (completed-span path) are unreachable no-ops — on the adapter's iOS-16 floor a
/// live receiver is always resolved through `*MeasurementStarted`/`*Ended`; the no-ops exist only
/// to satisfy the base protocols that the `Live*` sub-protocols refine.
@available(iOS 16.0, *)
extension OTelInstrumenter:
    LiveTTIMetricsReceiver,
    LiveRenderingMetricsReceiver,
    LiveFragmentTTIMetricsReceiver,
    LiveAppRenderingMetricsReceiver,
    LiveStartupTimeReceiver,
    HangsReceiver,
    WatchdogTerminationsReceiver,
    ViewControllerLeaksReceiver {

    // MARK: - TTIMetricsReceiver

    public func ttiMetricsReceived(metrics: TTIMetrics, screen: Screen) {}

    public func screenTTIMeasurementStarted(screen: Screen) -> (any MeasurementHandle)? {
        let name = identifierName(screen)
        let attrs = OTelSemanticConventions.Attribute.self
        let initialAttributes: [String: AttributeValue] = [
            attrs.screenName: .string(name),
        ]
        let span = emitter.startLiveSpan(
            spanName: emitter.prefixed(OTelSemanticConventions.SpanName.screenTTI(name)),
            startTime: now(),
            attributes: OTelSpanEmitter.SDKAttributeSet(
                values: initialAttributes,
                reservedKeys: OTelSDKKeys.screenTTI
            ),
            context: .screenTTI(ScreenContext(screenName: name))
        )
        guard let span else { return nil }
        return OTelSpanContext(span: span)
    }

    public func screenTTIMeasurementEnded(
        metrics: TTIMetrics,
        screen: Screen,
        context: (any MeasurementHandle)?
    ) {
        guard let ctx = context as? OTelSpanContext else { return }
        // shouldEmit gated at start; ScreenContext is fully known there and stable.
        let attrs = OTelSemanticConventions.Attribute.self
        if let ms = metrics.tti.milliseconds {
            ctx.span.setAttribute(key: attrs.screenTTIMs, value: .int(ms))
        }
        if let ms = metrics.ttfr.milliseconds {
            ctx.span.setAttribute(key: attrs.screenTTFRMs, value: .int(ms))
        }
        ctx.span.end(time: now())
    }

    // MARK: - RenderingMetricsReceiver

    public func renderingMetricsReceived(metrics: RenderingMetrics, screen: Screen) {}

    public func screenRenderingStarted(
        screen: Screen,
        sessionStarted: Date
    ) -> (any MeasurementHandle)? {
        let name = identifierName(screen)
        let attrs = OTelSemanticConventions.Attribute.self
        let initialAttributes: [String: AttributeValue] = [
            attrs.screenName: .string(name),
        ]
        // Anchor on the pre-async-hop wall-clock Date captured in `RenderingObserver`.
        let span = emitter.startLiveSpan(
            spanName: emitter.prefixed(OTelSemanticConventions.SpanName.screenRendering(name)),
            startTime: sessionStarted,
            attributes: OTelSpanEmitter.SDKAttributeSet(
                values: initialAttributes,
                reservedKeys: OTelSDKKeys.screenRendering
            ),
            context: .screenRendering(ScreenContext(screenName: name))
        )
        guard let span else { return nil }
        return OTelSpanContext(span: span)
    }

    public func screenRenderingEnded(
        metrics: RenderingMetrics,
        screen: Screen,
        context: (any MeasurementHandle)?
    ) {
        guard let ctx = context as? OTelSpanContext else { return }
        emitter.applyRenderingAttributes(span: ctx.span, metrics: metrics)
        ctx.span.end(time: now())
    }

    // MARK: - FragmentTTIMetricsReceiver

    public func fragmentTTIMetricsReceived(metrics: TTIMetrics, fragment: Fragment) {}

    public func fragmentTTIMeasurementStarted(fragment: Fragment) -> (any MeasurementHandle)? {
        let name = identifierName(fragment)
        let attrs = OTelSemanticConventions.Attribute.self
        let initialAttributes: [String: AttributeValue] = [
            attrs.fragmentName: .string(name),
        ]
        let span = emitter.startLiveSpan(
            spanName: emitter.prefixed(OTelSemanticConventions.SpanName.fragmentTTI(name)),
            startTime: now(),
            attributes: OTelSpanEmitter.SDKAttributeSet(
                values: initialAttributes,
                reservedKeys: OTelSDKKeys.fragmentTTI
            ),
            context: .fragmentTTI(FragmentContext(fragmentName: name))
        )
        guard let span else { return nil }
        return OTelSpanContext(span: span)
    }

    public func fragmentTTIMeasurementEnded(
        metrics: TTIMetrics,
        fragment: Fragment,
        context: (any MeasurementHandle)?
    ) {
        guard let ctx = context as? OTelSpanContext else { return }
        let attrs = OTelSemanticConventions.Attribute.self
        if let ms = metrics.tti.milliseconds {
            ctx.span.setAttribute(key: attrs.fragmentTTIMs, value: .int(ms))
        }
        if let ms = metrics.ttfr.milliseconds {
            ctx.span.setAttribute(key: attrs.fragmentTTFRMs, value: .int(ms))
        }
        ctx.span.end(time: now())
    }

    // MARK: - AppRenderingMetricsReceiver

    public func appRenderingMetricsReceived(metrics: RenderingMetrics) {
        appRenderingAccumulator.appRenderingMetricsReceived(metrics: metrics)
    }

    public func appRenderingSessionStarted(at startedAt: Date) {
        appRenderingAccumulator.appRenderingSessionStarted(at: startedAt)
    }

    public func appRenderingSessionEnded() {
        appRenderingAccumulator.appRenderingSessionEnded()
    }

    // MARK: - StartupTimeReceiver

    public func startupTimeReceived(_ data: StartupTimeData) {}

    public func startupMeasurementStarted() -> (any MeasurementHandle)? {
        // Retroactive: span window starts at process start (sysctl). Raw helper
        // because StartupTimeData isn't yet known — shouldEmit/attributeProvider deferred.
        let span = emitter.startLiveSpanRaw(
            spanName: emitter.prefixed(OTelSemanticConventions.SpanName.appStartup),
            startTime: PerformanceMonitoring.processStartTime,
            attributes: [:]
        )
        return OTelSpanContext(span: span)
    }

    public func startupMeasurementEnded(
        _ data: StartupTimeData,
        context: (any MeasurementHandle)?
    ) {
        guard let ctx = context as? OTelSpanContext else { return }
        let attrs = OTelSemanticConventions.Attribute.self
        var finalAttributes: [String: AttributeValue] = [:]
        if let ms = data.totalTime.milliseconds {
            finalAttributes[attrs.startupTotalTimeMs] = .int(ms)
        }
        if let ms = data.mainTime?.milliseconds {
            finalAttributes[attrs.startupMainTimeMs] = .int(ms)
        }
        if let ms = data.preMainTime?.milliseconds {
            finalAttributes[attrs.startupPremainTimeMs] = .int(ms)
        }
        finalAttributes[attrs.startupPrewarmed] = .bool(data.appStartInfo.appStartedWithPrewarming)

        // End = start + totalTime, matching the completed-span window for consistency.
        let durationInterval = data.totalTime.timeInterval ?? 0
        let endTime = PerformanceMonitoring.processStartTime.addingTimeInterval(durationInterval)
        emitter.finalizeLiveSpan(
            span: ctx.span,
            endTime: endTime,
            finalAttributes: OTelSpanEmitter.SDKAttributeSet(
                values: finalAttributes,
                reservedKeys: OTelSDKKeys.startup
            ),
            context: .startup(data)
        )
    }

    // MARK: - HangsReceiver

    public func fatalHangReceived(info: HangInfo) {
        // Fatal hangs detected post-facto on next launch (HangReporter.notifyAboutFatalHangs);
        // never paired with an in-process hangStarted. Defensive cancel guards a stale
        // live span just in case.
        hangContextLock.lock()
        let stale = currentHangContext
        currentHangContext = nil
        hangContextLock.unlock()
        stale?.cancel()
        emitter.emitFatalHangSpan(info: info)
    }

    public func nonFatalHangReceived(info: HangInfo) {
        hangContextLock.lock()
        let ctx = currentHangContext
        currentHangContext = nil
        hangContextLock.unlock()
        // Live-only: a non-fatal hang is always preceded by `hangStarted`, so `ctx` is non-nil in
        // steady state. A nil ctx (SDK enabled mid-hang — unreachable in practice) emits nothing.
        guard let ctx else { return }
        // End window = info.detectedAt + final duration to match the completed-span shape.
        // Re-stamp top screen and session id (may have changed since hangStarted).
        let attrs = OTelSemanticConventions.Attribute.self
        var finalAttributes: [String: AttributeValue] = [
            attrs.hangType: .string(OTelSemanticConventions.HangType.nonFatal),
        ]
        if let ms = info.duration.milliseconds {
            finalAttributes[attrs.hangDurationMs] = .int(ms)
        }
        if let topScreen = info.appRuntimeInfo.openedScreens.last {
            finalAttributes[attrs.hangTopScreen] = .string(topScreen)
        }
        if let sessionId = info.sessionId {
            finalAttributes[attrs.appSessionId] = .string(sessionId)
        }
        let durationInterval = info.duration.timeInterval ?? 0
        let endTime = (info.detectedAt ?? now()).addingTimeInterval(durationInterval)
        emitter.finalizeLiveSpan(
            span: ctx.span,
            endTime: endTime,
            finalAttributes: OTelSpanEmitter.SDKAttributeSet(
                values: finalAttributes,
                reservedKeys: OTelSDKKeys.hang
            ),
            context: .nonFatalHang(info)
        )
    }

    public func hangStarted(info: HangInfo) {
        // Raw helper: at hangStarted info.duration is a threshold-crossing snapshot and
        // fatal-vs-non-fatal is unknown; shouldEmit/attributeProvider deferred to
        // nonFatalHangReceived's finalizeLiveSpan against the complete .nonFatalHang context.
        let attrs = OTelSemanticConventions.Attribute.self
        var initialAttributes: [String: AttributeValue] = [
            attrs.hangDuringStartup: .bool(info.duringStartup),
        ]
        if let topScreen = info.appRuntimeInfo.openedScreens.last {
            initialAttributes[attrs.hangTopScreen] = .string(topScreen)
        }
        if let sessionId = info.sessionId {
            initialAttributes[attrs.appSessionId] = .string(sessionId)
        }
        // Anchor on detectedAt — matches the completed-span shape (emitHangSpan).
        let startTime = info.detectedAt ?? now()
        // Build + install the span under the lock so a concurrent nonFatalHangReceived never sees an
        // interim currentHangContext == nil and falls back to the completed-span emit path.
        // `autoTerminate: false`: a fatal hang already has an authoritative next-launch record
        // (`fatalHangReceived`), so an auto-terminated orphan here would just double-count it. Without
        // the attribute, Embrace drops the unended span on the dying session — leaving the one record.
        hangContextLock.lock()
        let previous = currentHangContext
        let span = emitter.startLiveSpanRaw(
            spanName: emitter.prefixed(OTelSemanticConventions.SpanName.appHang),
            startTime: startTime,
            attributes: initialAttributes,
            autoTerminate: false
        )
        currentHangContext = OTelSpanContext(span: span)
        hangContextLock.unlock()
        previous?.cancel()
    }

    // MARK: - WatchdogTerminationsReceiver

    public func watchdogTerminationReceived(_ data: WatchdogTerminationData) {
        emitter.emitWatchdogTerminationSpan(data: data)
    }

    // MARK: - ViewControllerLeaksReceiver

    public func viewControllerLeakReceived(viewController: UIViewController) {
        logEmitter.emitViewControllerLeakLog(
            viewController: viewController,
            appStartedWithPrewarming: PerformanceMonitoring.appStartInfo.appStartedWithPrewarming
        )
    }

    // No `shouldTrack(viewController:)` override — picks up the protocol
    // extension default (`true`). Per-VC opt-out is wired chain-wide through
    // `MultiViewControllerLeaksReceiver`'s `shouldTrack:` predicate, not
    // per-receiver, so that squeak and OTel pipelines stay in lockstep when
    // a host filter (e.g. `UINavigationController` exclusion) is applied.
}
