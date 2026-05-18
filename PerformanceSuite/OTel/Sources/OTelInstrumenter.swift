//
//  OTelInstrumenter.swift
//  PerformanceSuiteOTel
//
//  Created by Ahmed Nafei on 30/04/2026.
//

import Foundation
import OpenTelemetryApi
import UIKit

// In SwiftPM `PerformanceSuiteOTel` is its own target, so we must explicitly
// import the sibling `PerformanceSuite` module. In CocoaPods the OTel subspec
// is compiled as part of the single `PerformanceSuite` framework, so the
// `PerformanceSuite` types are already in scope and a self-import would fail.
#if canImport(PerformanceSuiteOTel)
import PerformanceSuite
#endif

/// Adapter that turns every PerformanceSuite metric into an OpenTelemetry span.
///
/// `OTelInstrumenter` conforms to **all** PerformanceSuite receiver protocols
/// and emits one OTel span per signal received. Spans are recorded as completed
/// (start time + end time set together at emission), which is the simplest
/// shape that flows through any standard OTel pipeline.
///
/// ## Generic parameters
///
/// `OTelInstrumenter` is generic over the host app's `Screen` and `Fragment`
/// identifier types. The generics avoid `Any` at the boundary so the
/// instrumenter can be wrapped inside ``MultiTTIMetricsReceiver`` /
/// ``MultiFragmentTTIMetricsReceiver`` without losing the type's screen
/// identity.
///
/// For an OTel-only setup with view-controller-typed screens, instantiate
/// directly with no parameters:
///
///     let otel = OTelInstrumenter<UIViewController, String>()
///
/// For a typed setup that participates in dual-emit via a `Multi*Receiver`,
/// pass `Screen` / `Fragment` matching the rest of the app's config (the
/// `screenIdentifier` closure is then provided by the multi-receiver, so
/// `OTelInstrumenter` can leave it unset).
///
/// ## TracerProvider resolution
///
/// The OTel tracer is **lazily** fetched from the global
/// `OpenTelemetry.instance.tracerProvider` at first emission unless an explicit
/// provider is injected. PerformanceSuite typically initialises before the
/// OTel SDK (for example the Embrace SDK in BookingObservability), so eager
/// resolution would freeze the no-op `DefaultTracerProvider` and silently drop
/// every span.
///
/// ## Identifier conversion
///
/// Span names embed the screen / fragment identifier as a string. For
/// `String`-backed `RawRepresentable` enums (the common case in the host app)
/// the `rawValue` is used; otherwise the value is rendered via
/// `String(describing:)`. This matches the semantics used by the existing
/// PerformanceSuite squeak path and keeps OTel span names stable across
/// renames in Swift code.
public final class OTelInstrumenter<Screen, Fragment>:
    TTIMetricsReceiver,
    RenderingMetricsReceiver,
    FragmentTTIMetricsReceiver,
    AppRenderingMetricsReceiver,
    StartupTimeReceiver,
    HangsReceiver,
    WatchdogTerminationsReceiver {
    public typealias ScreenIdentifier = Screen
    public typealias FragmentIdentifier = Fragment

    private let _screenIdentifier: ((UIViewController) -> Screen?)?
    private let emitter: OTelSpanEmitter

    /// - Parameters:
    ///   - screenIdentifier: Optional closure to map view controllers to
    ///     `Screen`. When `nil`:
    ///       * If `Screen == UIViewController`, the default behaviour
    ///         (track main-bundle view controllers) is used — matching
    ///         PerformanceSuite's own default.
    ///       * Otherwise this method returns `nil`, which is the right
    ///         behaviour when the instrumenter is wrapped inside a
    ///         `Multi*Receiver` whose own closure is the source of truth.
    ///   - tracerProvider: Inject a custom provider for tests or special
    ///     setups. When `nil`, the global `OpenTelemetry.instance.tracerProvider`
    ///     is resolved at first emission.
    ///   - instrumentationName: Reported on every span. Backends use this to
    ///     filter PerformanceSuite spans. Defaults to `"perfsuite-ios"`.
    ///   - instrumentationVersion: Optional version string reported alongside
    ///     the instrumentation name.
    ///   - spanNamePrefix: Optional prefix prepended to every span name with a
    ///     dot separator. For example, `"bookingcom"` turns `"app-startup"`
    ///     into `"bookingcom.app-startup"`. Useful when multiple apps share an
    ///     OTel pipeline and need namespaced span names. `nil` (the default)
    ///     emits unprefixed names.
    ///   - attributeProvider: Optional closure invoked once per emission with
    ///     the matching ``PerformanceSuiteSignalContext``. The returned
    ///     attributes are merged onto the span (or log record) via
    ///     ``mergeOTelAttributes(sdkSet:sdkSetKeys:provider:context:)``.
    ///     SDK-set semantic-convention keys win on collision; host attributes
    ///     matching SDK-reserved keys are silently dropped at the merge.
    public init(
        screenIdentifier: ((UIViewController) -> Screen?)? = nil,
        tracerProvider: (any TracerProvider)? = nil,
        instrumentationName: String = OTelSemanticConventions.defaultInstrumentationName,
        instrumentationVersion: String? = nil,
        spanNamePrefix: String? = nil,
        attributeProvider: OTelAttributeProvider? = nil
    ) {
        self._screenIdentifier = screenIdentifier
        self.emitter = OTelSpanEmitter(
            tracerProvider: tracerProvider,
            instrumentationName: instrumentationName,
            instrumentationVersion: instrumentationVersion,
            spanNamePrefix: spanNamePrefix,
            attributeProvider: attributeProvider
        )
    }

    /// Test-only initializer that allows injecting a deterministic clock.
    init(
        screenIdentifier: ((UIViewController) -> Screen?)?,
        tracerProvider: (any TracerProvider)?,
        instrumentationName: String,
        instrumentationVersion: String?,
        spanNamePrefix: String? = nil,
        attributeProvider: OTelAttributeProvider? = nil,
        now: @escaping () -> Date
    ) {
        self._screenIdentifier = screenIdentifier
        self.emitter = OTelSpanEmitter(
            tracerProvider: tracerProvider,
            instrumentationName: instrumentationName,
            instrumentationVersion: instrumentationVersion,
            spanNamePrefix: spanNamePrefix,
            attributeProvider: attributeProvider,
            now: now
        )
    }

    // MARK: - ScreenMetricsReceiver

    public func screenIdentifier(for viewController: UIViewController) -> Screen? {
        if let provider = _screenIdentifier {
            return provider(viewController)
        }
        if Screen.self == UIViewController.self {
            // Mirror PerformanceSuite's default: track view controllers from
            // the main bundle only.
            guard Bundle(for: type(of: viewController)) == Bundle.main else { return nil }
            return viewController as? Screen
        }
        // The instrumenter is being used as part of a Multi*Receiver — the
        // screenIdentifier closure on the multi-receiver supplies the mapping,
        // and PerformanceSuite never calls this method on us directly.
        return nil
    }

    // MARK: - TTIMetricsReceiver

    public func ttiMetricsReceived(metrics: TTIMetrics, screen: Screen) {
        emitter.emitScreenTTISpan(screenName: identifierName(screen), metrics: metrics)
    }

    // MARK: - RenderingMetricsReceiver

    public func renderingMetricsReceived(metrics: RenderingMetrics, screen: Screen) {
        emitter.emitScreenRenderingSpan(screenName: identifierName(screen), metrics: metrics)
    }

    // MARK: - FragmentTTIMetricsReceiver

    public func fragmentTTIMetricsReceived(metrics: TTIMetrics, fragment: Fragment) {
        emitter.emitFragmentTTISpan(fragmentName: identifierName(fragment), metrics: metrics)
    }

    // MARK: - AppRenderingMetricsReceiver

    public func appRenderingMetricsReceived(metrics: RenderingMetrics) {
        emitter.emitAppRenderingSpan(metrics: metrics)
    }

    // MARK: - StartupTimeReceiver

    public func startupTimeReceived(_ data: StartupTimeData) {
        // The OTel side always emits, even on
        // prewarmed launches. The `app.startup.prewarmed` attribute lets
        // backends filter or weight prewarm samples instead of dropping them.
        emitter.emitStartupSpan(data: data)
    }

    // MARK: - HangsReceiver

    public func fatalHangReceived(info: HangInfo) {
        emitter.emitFatalHangSpan(info: info)
    }

    public func nonFatalHangReceived(info: HangInfo) {
        emitter.emitNonFatalHangSpan(info: info)
    }

    public func hangStarted(info: HangInfo) {
        // `hangStarted` is an in-progress signal; no completed span to record.
        // A future live-spans iteration will turn this into a span-start event.
    }

    // MARK: - WatchdogTerminationsReceiver

    public func watchdogTerminationReceived(_ data: WatchdogTerminationData) {
        emitter.emitWatchdogTerminationSpan(data: data)
    }

    // MARK: - Identifier conversion

    /// Convert an arbitrary identifier to the string form used in span names
    /// and attribute values.
    ///
    /// Strategy:
    /// 1. If the identifier is a `String`-backed `RawRepresentable` (the common
    ///    case for `enum Screen: String`), emit the raw value. This produces
    ///    stable, dashboard-friendly names like `"search_results"` instead of
    ///    Swift-mangled `"PerformanceScreen.searchResults"`.
    /// 2. Otherwise fall back to `String(describing:)`. Acceptable for
    ///    `String` identifiers (which become themselves) and for ad-hoc enum
    ///    types.
    private func identifierName<T>(_ identifier: T) -> String {
        if let raw = identifier as? any RawRepresentable,
           let str = raw.rawValue as? String {
            return str
        }
        return String(describing: identifier)
    }
}
