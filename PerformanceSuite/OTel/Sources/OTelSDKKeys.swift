//
//  OTelSDKKeys.swift
//  PerformanceSuiteOTel
//
//  Created by Ahmed Nafei on 18/05/2026.
//

import Foundation

/// Per-signal sets of attribute keys the SDK reserves. These are passed as
/// `sdkSetKeys` to ``mergeOTelAttributes(sdkSet:sdkSetKeys:provider:context:)``
/// so any host attribute matching one of them is silently dropped at the
/// merge — preventing host code from overwriting an SDK semantic-convention
/// value (whether or not the SDK actually set it for *this* particular
/// emission; some attributes are conditional on the metric value being
/// present).
///
/// Extracted from the emitters so a future maintainer can scan the entire
/// SDK-reserved key universe in one place when adding new attributes.
enum OTelSDKKeys {

    static let startup: Set<String> = [
        OTelSemanticConventions.Attribute.startupTotalTimeMs,
        OTelSemanticConventions.Attribute.startupMainTimeMs,
        OTelSemanticConventions.Attribute.startupPremainTimeMs,
        OTelSemanticConventions.Attribute.startupPrewarmed,
    ]

    static let screenTTI: Set<String> = [
        OTelSemanticConventions.Attribute.screenName,
        OTelSemanticConventions.Attribute.screenTTIMs,
        OTelSemanticConventions.Attribute.screenTTFRMs,
    ]

    static let fragmentTTI: Set<String> = [
        OTelSemanticConventions.Attribute.fragmentName,
        OTelSemanticConventions.Attribute.fragmentTTIMs,
        OTelSemanticConventions.Attribute.fragmentTTFRMs,
    ]

    static let screenRendering: Set<String> = [
        OTelSemanticConventions.Attribute.screenName,
        OTelSemanticConventions.Attribute.renderingTotalFrames,
        OTelSemanticConventions.Attribute.renderingDroppedFrames,
        OTelSemanticConventions.Attribute.renderingSlowFrames,
        OTelSemanticConventions.Attribute.renderingFreezeTimeMs,
        OTelSemanticConventions.Attribute.renderingSessionDurationMs,
    ]

    static let appRendering: Set<String> = [
        OTelSemanticConventions.Attribute.renderingTotalFrames,
        OTelSemanticConventions.Attribute.renderingDroppedFrames,
        OTelSemanticConventions.Attribute.renderingSlowFrames,
        OTelSemanticConventions.Attribute.renderingFreezeTimeMs,
        OTelSemanticConventions.Attribute.renderingSessionDurationMs,
        OTelSemanticConventions.Attribute.appSessionDurationMs,
        // Auto-termination key (when set) is reserved dynamically by OTelSpanEmitter.reservedKeys(_:).
    ]

    static let hang: Set<String> = [
        OTelSemanticConventions.Attribute.hangType,
        OTelSemanticConventions.Attribute.hangDuringStartup,
        OTelSemanticConventions.Attribute.hangDurationMs,
        OTelSemanticConventions.Attribute.hangTopScreen,
        OTelSemanticConventions.Attribute.appSessionId,
    ]

    static let watchdogTermination: Set<String> = [
        OTelSemanticConventions.Attribute.memoryWarningsCount,
    ]

    static let viewControllerLeak: Set<String> = [
        OTelSemanticConventions.Attribute.viewControllerClassName,
        OTelSemanticConventions.Attribute.viewControllerIdentifier,
        OTelSemanticConventions.Attribute.startupPrewarmed,
    ]
}
