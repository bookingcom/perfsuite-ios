//
//  OTelInstrumenter+LiveRenderingMetrics.swift
//  PerformanceSuiteOTel
//
//  Created by Gleb Tarasov on 20/11/2026.
//

import Foundation
import OpenTelemetryApi

#if canImport(PerformanceSuiteOTel)
import PerformanceSuite
#endif

// fixFatalHangOnResignActive: on cleanup, move these into OTelInstrumenter+Receivers.swift, replacing the methods without `liveMetrics`.
/// Rendering spans that end themselves with their metrics so far when the app resigns active.
@available(iOS 16.0, *)
extension OTelInstrumenter {

    // fixFatalHangOnResignActive: variant implementation; keep on cleanup, replacing `screenRenderingStarted(screen:sessionStarted:)`.
    public func screenRenderingStarted(
        screen: Screen,
        sessionStarted: Date,
        liveMetrics: LiveRenderingMetrics
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
        return OTelRenderingSpanContext(
            span: span, emitter: emitter, now: now, liveMetrics: liveMetrics, appStateListener: appStateListenerFactory())
    }

    // fixFatalHangOnResignActive: variant implementation; keep on cleanup, replacing `appRenderingSessionStarted(at:)`.
    public func appRenderingSessionStarted(at startedAt: Date, liveMetrics: LiveRenderingMetrics) {
        appRenderingAccumulator.appRenderingSessionStarted(at: startedAt, liveMetrics: liveMetrics)
    }
}
