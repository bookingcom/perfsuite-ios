//
//  OTelSemanticConventions.swift
//  PerformanceSuiteOTel
//
//  Created by Ahmed Nafei on 30/04/2026.
//

import Foundation

/// Span names and attribute keys used by ``OTelInstrumenter`` when emitting
/// PerformanceSuite metrics as OpenTelemetry spans.
///
/// Centralising these as constants gives consumers a single place to reference
/// when building backend dashboards or alerting rules. Constants are namespaced
/// by concern (`SpanName`, `Attribute`) so call sites stay readable:
///
///     spanBuilder.setAttribute(
///         key: OTelSemanticConventions.Attribute.screenTTIMs,
///         value: ttiMilliseconds
///     )
public enum OTelSemanticConventions {

    public enum SpanName {
        public static let appStartup = "app-startup"
        public static let appRendering = "app-rendering"
        public static let appHang = "app-hang"
        public static let appWatchdogTermination = "app-watchdog-termination"

        public static func screenTTI(_ screenName: String) -> String {
            "screen-tti.\(screenName)"
        }

        public static func fragmentTTI(_ fragmentName: String) -> String {
            "fragment-tti.\(fragmentName)"
        }

        public static func screenRendering(_ screenName: String) -> String {
            "screen-rendering.\(screenName)"
        }
    }

    public enum Attribute {
        // Startup
        public static let startupTotalTimeMs = "app.startup.total_time.ms"
        public static let startupMainTimeMs = "app.startup.main_time.ms"
        public static let startupPremainTimeMs = "app.startup.premain_time.ms"
        public static let startupPrewarmed = "app.startup.prewarmed"

        // Screen TTI
        public static let screenName = "screen.name"
        public static let screenTTIMs = "screen.tti.ms"
        public static let screenTTFRMs = "screen.ttfr.ms"

        // Fragment TTI
        public static let fragmentName = "fragment.name"
        public static let fragmentTTIMs = "fragment.tti.ms"
        public static let fragmentTTFRMs = "fragment.ttfr.ms"

        // Rendering (screen-level + app-level share these keys)
        public static let renderingTotalFrames = "rendering.total_frames"
        public static let renderingDroppedFrames = "rendering.dropped_frames"
        public static let renderingSlowFrames = "rendering.slow_frames"
        public static let renderingFreezeTimeMs = "rendering.freeze_time.ms"
        public static let renderingSessionDurationMs = "rendering.session_duration.ms"

        // Hangs
        public static let hangType = "hang.type"
        public static let hangDurationMs = "hang.duration.ms"
        public static let hangDuringStartup = "hang.during_startup"
        public static let hangTopScreen = "hang.top_screen"

        // App session — set on per-session app-rendering spans and on hang
        // spans (sourced from `HangInfo.sessionId`).
        public static let appSessionId = "app.session.id"
        public static let appSessionDurationMs = "app.session.duration.ms"

        /// The backend's session-bucketing key. A session processor stamps this = the CURRENT session
        /// on every span at start and the exporter buckets spans into the session payload by it. This is
        /// the generic OpenTelemetry session key (Embrace's `SpanSemantics.keySessionId` is the same
        /// `"session.id"`), so it's safe to hardcode here rather than inject — a post-facto fatal-hang
        /// span re-stamps it (post-`startSpan`) with the session the hang happened in.
        public static let sessionId = "session.id"

        // Watchdog termination
        public static let appState = "app.state"
        public static let memoryWarningsCount = "memory.warnings_count"
        public static let deviceRamMb = "device.ram.mb"

        // View-controller leak
        public static let viewControllerClassName = "vc.class_name"
        public static let viewControllerIdentifier = "vc.identifier"

        // Device / OS (set on app-level spans where useful)
        public static let deviceModel = "device.model"
        public static let osName = "os.name"
        public static let osVersion = "os.version"
    }

    /// String values that appear as the `body` of OTel log records emitted by
    /// ``OTelInstrumenter``. Centralised so backends can pin filters on stable
    /// strings.
    public enum LogBody {
        public static let viewControllerLeak = "view_controller_leak"
    }

    /// String values that appear in the `hang.type` attribute. Kept narrow on
    /// purpose so backend dashboards don't accumulate freeform variants.
    public enum HangType {
        public static let fatal = "fatal"
        public static let nonFatal = "non_fatal"
    }

    /// Strings emitted in the `app.state` attribute on watchdog-termination
    /// spans, mirroring the cases of `UIApplication.State`.
    public enum AppState {
        public static let active = "active"
        public static let inactive = "inactive"
        public static let background = "background"
        public static let unknown = "unknown"
    }

    /// Stable string for the `os.name` attribute.
    public static let osNameValue = "iOS"

    /// Default instrumentation name reported on every ``OTelInstrumenter`` span.
    public static let defaultInstrumentationName = "perfsuite-ios"
}
