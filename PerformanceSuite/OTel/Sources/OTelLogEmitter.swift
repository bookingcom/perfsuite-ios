//
//  OTelLogEmitter.swift
//  PerformanceSuiteOTel
//
//  Created by Ahmed Nafei on 18/05/2026.
//

import Foundation
import OpenTelemetryApi
import UIKit

#if canImport(PerformanceSuiteOTel)
import PerformanceSuite
#endif

/// Internal helper that emits OTel `LogRecord`s for PerformanceSuite signals
/// that don't have a meaningful duration (currently view-controller leaks).
///
/// Sibling of ``OTelSpanEmitter``: the same lazy-provider-resolution and
/// SDK-key-guarding patterns apply, just against the OTel `Logger` /
/// `LogRecordBuilder` API instead of `Tracer` / `SpanBuilder`.
///
/// Design points:
///
/// * The `LoggerProvider` is **lazily resolved at first emission**, not at
///   construction. PerformanceSuite typically initialises before the OTel SDK
///   (Embrace) registers the global provider — eagerly capturing
///   `OpenTelemetry.instance.loggerProvider` at init time would freeze the
///   no-op `DefaultLoggerProvider` and silently drop every leak record.
///   Embrace registers a real provider via `EmbraceOTel.setup(...)` before its
///   own tracker init completes, so by the time any PerformanceSuite signal
///   is delivered to ``OTelInstrumenter`` the global is already set.
///
/// * Attributes are merged through the shared
///   ``mergeOTelAttributes(sdkSet:sdkSetKeys:provider:context:)`` helper so
///   the SDK-key guard runs uniformly across spans and log records.
final class OTelLogEmitter {

    private let loggerProvider: (any LoggerProvider)?
    private let instrumentationName: String
    private let attributeProvider: OTelAttributeProvider?
    private let now: () -> Date

    init(
        loggerProvider: (any LoggerProvider)?,
        instrumentationName: String,
        attributeProvider: OTelAttributeProvider? = nil,
        now: @escaping () -> Date = Date.init
    ) {
        self.loggerProvider = loggerProvider
        self.instrumentationName = instrumentationName
        self.attributeProvider = attributeProvider
        self.now = now
    }

    // MARK: - Logger resolution

    private func logger() -> any Logger {
        let provider = loggerProvider ?? OpenTelemetry.instance.loggerProvider
        return provider.get(instrumentationScopeName: instrumentationName)
    }

    // MARK: - View-controller leak

    /// Emits a `WARN` log record describing a leaked view controller. The body
    /// is the constant string ``OTelSemanticConventions/LogBody/viewControllerLeak``;
    /// the class-name attribute is refined via ``RootViewIntrospectable`` when
    /// available so SwiftUI hosting controllers carry the meaningful root-view
    /// type instead of `UIHostingController<…>`.
    func emitViewControllerLeakLog(
        viewController: UIViewController,
        appStartedWithPrewarming: Bool
    ) {
        let attrs = OTelSemanticConventions.Attribute.self
        let sdkAttributes: [String: AttributeValue] = [
            attrs.viewControllerClassName: .string(className(of: viewController)),
            attrs.viewControllerIdentifier: .string(viewController.description),
            attrs.startupPrewarmed: .bool(appStartedWithPrewarming),
        ]

        let merged = mergeOTelAttributes(
            sdkSet: sdkAttributes,
            sdkSetKeys: OTelSDKKeys.viewControllerLeak,
            provider: attributeProvider,
            context: .viewControllerLeak(viewController)
        )

        let timestamp = now()
        _ = logger().logRecordBuilder()
            .setSeverity(.warn)
            .setBody(.string(OTelSemanticConventions.LogBody.viewControllerLeak))
            .setTimestamp(timestamp)
            .setObservedTimestamp(timestamp)
            .setAttributes(merged)
            .emit()
    }

    // MARK: - Class-name refinement

    /// Refines the class name for SwiftUI-hosted view controllers. When the
    /// view controller conforms to ``RootViewIntrospectable`` (in practice:
    /// `UIHostingController`), the introspected root view's type is used so
    /// the log carries the user-meaningful SwiftUI type instead of the
    /// generic-mangled `UIHostingController<…>`. Mirrors the squeak path's
    /// two-pass refinement at the host-side classifier — both paths rely on
    /// the same ``RootViewIntrospectable`` protocol contract, so they cannot
    /// drift independently.
    private func className(of viewController: UIViewController) -> String {
        if let introspectable = viewController as? RootViewIntrospectable {
            return String(describing: type(of: introspectable.introspectRootView()))
        }
        return String(describing: type(of: viewController))
    }
}
