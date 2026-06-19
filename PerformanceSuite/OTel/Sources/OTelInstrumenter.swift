//
//  OTelInstrumenter.swift
//  PerformanceSuiteOTel
//
//  Created by Ahmed Nafei on 30/04/2026.
//

import Foundation
import OpenTelemetryApi
import UIKit

// SwiftPM: OTel is a separate target, so import the sibling core module. CocoaPods compiles both as
// one framework, where this self-import is skipped.
#if canImport(PerformanceSuiteOTel)
import PerformanceSuite
#endif

/// Adapter that turns every PerformanceSuite metric into an OpenTelemetry span.
///
/// **Live-only**: signals with a start (screen/fragment TTI, rendering, startup, hangs, app-rendering)
/// emit a live span; post-facto signals (fatal hang, watchdog, VC leaks) emit a completed span/log; the
/// base `*Received` callbacks are unused no-ops. Requires **iOS 16** — live dispatch for the
/// associated-type signals uses a constrained-existential cast (iOS-16 runtime). Core stays iOS-15.
///
/// Generic over `Screen`/`Fragment` so screen identity survives a `Multi*Receiver` (no `Any` boundary).
/// The tracer resolves lazily at first emission (PerformanceSuite usually inits before the OTel SDK
/// registers its global, so eager resolution would freeze the no-op provider).
@available(iOS 16.0, *)
public final class OTelInstrumenter<Screen, Fragment> {
    public typealias ScreenIdentifier = Screen
    public typealias FragmentIdentifier = Fragment

    private let _screenIdentifier: ((UIViewController) -> Screen?)?
    // Internal (not private) so the receiver conformances in OTelInstrumenter+Receivers.swift reach them.
    let emitter: OTelSpanEmitter
    let logEmitter: OTelLogEmitter
    let appRenderingAccumulator: AppRenderingSessionAccumulator
    let now: () -> Date

    /// In-flight hang span. Guarded by `hangContextLock` since the public receiver methods could be
    /// called off the documented serial consumerQueue.
    var currentHangContext: OTelSpanContext?
    let hangContextLock = NSLock()

    /// - Parameters:
    ///   - screenIdentifier: Maps view controllers to `Screen`. `nil` → main-bundle VCs when
    ///     `Screen == UIViewController`, else `nil` (the wrapping `Multi*Receiver`'s closure is the source).
    ///   - tracerProvider / loggerProvider: Inject for tests; `nil` resolves the global lazily at first emission.
    ///   - instrumentationName / instrumentationVersion: Reported on every span; backends filter on them.
    ///   - spanNamePrefix: Optional dot-prefix on span names (`"bookingcom"` → `"bookingcom.app-startup"`).
    ///   - attributeProvider: Invoked once per emission with the signal context; result merged onto the
    ///     span (SDK-reserved keys win; host collisions dropped).
    ///   - shouldEmit: Per-emission gate. `false` suppresses start-gated spans; for deferred-context live
    ///     spans (startup, hangs, app-rendering) it ends with `Status.error("shouldEmit_rejected")` instead.
    ///   - autoTerminationAttribute: Optional `(key, value)` stamped on live spans at start for a backend
    ///     to close on unclean exit. `nil` = vendor-neutral. Embrace: `("emb.auto_termination.code", "user_abandon")`.
    ///   - now: Clock for deterministic tests.
    public init(
        screenIdentifier: ((UIViewController) -> Screen?)? = nil,
        tracerProvider: (any TracerProvider)? = nil,
        loggerProvider: (any LoggerProvider)? = nil,
        instrumentationName: String = OTelSemanticConventions.defaultInstrumentationName,
        instrumentationVersion: String? = nil,
        spanNamePrefix: String? = nil,
        attributeProvider: OTelAttributeProvider? = nil,
        shouldEmit: ((PerformanceSuiteSignalContext) -> Bool)? = nil,
        autoTerminationAttribute: (key: String, value: String)? = nil,
        now: @escaping () -> Date = Date.init
    ) {
        self._screenIdentifier = screenIdentifier
        self.now = now
        let emitter = OTelSpanEmitter(
            tracerProvider: tracerProvider,
            instrumentationName: instrumentationName,
            instrumentationVersion: instrumentationVersion,
            spanNamePrefix: spanNamePrefix,
            attributeProvider: attributeProvider,
            shouldEmit: shouldEmit,
            autoTerminationAttribute: autoTerminationAttribute,
            now: now
        )
        self.emitter = emitter
        self.logEmitter = OTelLogEmitter(
            loggerProvider: loggerProvider,
            instrumentationName: instrumentationName,
            attributeProvider: attributeProvider,
            shouldEmit: shouldEmit,
            now: now
        )
        self.appRenderingAccumulator = AppRenderingSessionAccumulator(
            emitter: emitter,
            now: now
        )
    }

    // MARK: - ScreenMetricsReceiver

    public func screenIdentifier(for viewController: UIViewController) -> Screen? {
        if let provider = _screenIdentifier {
            return provider(viewController)
        }
        if Screen.self == UIViewController.self {
            // PerformanceSuite default: main-bundle VCs only.
            guard Bundle(for: type(of: viewController)) == Bundle.main else { return nil }
            return viewController as? Screen
        }
        // Wrapped in a Multi*Receiver — its closure supplies the mapping; this is never called directly.
        return nil
    }

    // MARK: - Identifier conversion

    /// String form of an identifier for span names / attributes (rawValue for String-backed
    /// RawRepresentable, else `String(describing:)`). `UIViewController` is special-cased to its class
    /// name because `String(describing:)` on an instance embeds the heap pointer → unbounded cardinality.
    func identifierName<T>(_ identifier: T) -> String {
        if let raw = identifier as? any RawRepresentable,
           let str = raw.rawValue as? String {
            return str
        }
        if let viewController = identifier as? UIViewController {
            return String(describing: type(of: viewController))
        }
        return String(describing: identifier)
    }
}
