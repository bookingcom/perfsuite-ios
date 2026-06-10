//
//  PerformanceSuiteSignal.swift
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

// MARK: - Signal kind discriminator

/// Discriminator-only enum exposed for tag/filter use and for tests that don't
/// care about payload contents.
///
/// Use ``PerformanceSuiteSignalContext/kind`` for metric tags, feature-flag
/// gating, and assertion helpers in tests. Consumers writing enrichment closures
/// should `switch` on the context itself instead — the exhaustive switch is
/// what gives the compiler-flagged-future-signal guarantee.
public enum PerformanceSuiteSignalKind: String, CaseIterable, Sendable {
    case startup
    case screenTTI
    case fragmentTTI
    case screenRendering
    case appRendering
    case fatalHang
    case nonFatalHang
    case watchdogTermination
    case viewControllerLeak
}

// MARK: - Signal context (hybrid enum)

/// Context handed to ``OTelAttributeProvider`` immediately before each
/// PerformanceSuite signal is emitted as an OTel span or log record.
///
/// Each case carries the most-direct usable payload for its signal:
///
/// - **Generic-erased projections** (`screenTTI`, `fragmentTTI`,
///   `screenRendering`, `appRendering`) carry a small projection struct.
///   These signals are generic over the host's `Screen` / `Fragment` types in
///   `PerformanceSuite`, and the projection erases those generic parameters
///   so ``OTelAttributeProvider``'s closure type stays non-generic.
///
/// - **Direct SDK payloads** (`startup`, `fatalHang`, `nonFatalHang`,
///   `watchdogTermination`, `viewControllerLeak`) carry the SDK's own public
///   types (`StartupTimeData`, `HangInfo`, `WatchdogTerminationData`,
///   `UIViewController`). Hosts can read every public field of the bound
///   payload — for example, a `shouldEmit` filter that drops prewarmed
///   startups can read `data.appStartInfo.appStartedWithPrewarming` directly.
public enum PerformanceSuiteSignalContext {

    case startup(StartupTimeData)
    case screenTTI(ScreenContext)
    case fragmentTTI(FragmentContext)
    case screenRendering(ScreenContext)
    case appRendering(AppRenderingContext)

    case fatalHang(HangInfo)
    case nonFatalHang(HangInfo)
    case watchdogTermination(WatchdogTerminationData)
    case viewControllerLeak(UIViewController)

    /// Discriminator-only view for callers that don't need the payload
    /// (e.g. logging, metrics tags, feature-flag gating).
    public var kind: PerformanceSuiteSignalKind {
        switch self {
        case .startup:              return .startup
        case .screenTTI:            return .screenTTI
        case .fragmentTTI:          return .fragmentTTI
        case .screenRendering:      return .screenRendering
        case .appRendering:         return .appRendering
        case .fatalHang:            return .fatalHang
        case .nonFatalHang:         return .nonFatalHang
        case .watchdogTermination:  return .watchdogTermination
        case .viewControllerLeak:   return .viewControllerLeak
        }
    }
}

// MARK: - Generic-erased projection structs

/// Carried by ``PerformanceSuiteSignalContext/appRendering(_:)``. Holds the
/// wall-clock window of the app-foreground session being emitted —
/// `sessionStartedAt` is captured at `UIApplication.didBecomeActiveNotification`,
/// `sessionEndedAt` at `UIApplication.didEnterBackgroundNotification`.
public struct AppRenderingContext: Sendable, Equatable {
    public let sessionStartedAt: Date
    public let sessionEndedAt: Date

    public init(sessionStartedAt: Date, sessionEndedAt: Date) {
        self.sessionStartedAt = sessionStartedAt
        self.sessionEndedAt = sessionEndedAt
    }
}

/// Carried by ``PerformanceSuiteSignalContext/screenTTI(_:)`` and
/// ``PerformanceSuiteSignalContext/screenRendering(_:)``. `screenName` is
/// computed by ``OTelInstrumenter`` from its `screenIdentifier` closure (or
/// the default identifier function) and is always non-nil at construction, so
/// consumers don't need to handle a `nil` case.
public struct ScreenContext: Sendable, Equatable {
    public let screenName: String
    public init(screenName: String) {
        self.screenName = screenName
    }
}

/// Carried by ``PerformanceSuiteSignalContext/fragmentTTI(_:)``. `fragmentName`
/// only — perfsuite-ios fragments are screen-independent at the SDK level
/// (`PerformanceMonitoring.startFragmentTTI(fragment:)` does not take a screen),
/// so there is no SDK-side source of truth for screen correlation at this
/// construction site. Hosts that track screen-fragment correlation themselves
/// can populate the additional context through the returned attribute
/// dictionary.
public struct FragmentContext: Sendable, Equatable {
    public let fragmentName: String
    public init(fragmentName: String) {
        self.fragmentName = fragmentName
    }
}

// MARK: - Host enrichment hook

/// Closure invoked once per OTel span (or log record) emission, receiving the
/// matching ``PerformanceSuiteSignalContext`` for the signal about to be
/// emitted. Returns extra `[String: AttributeValue]` to merge onto the span /
/// record. Host attributes matching a key the SDK reserves for the current
/// signal are silently dropped at the merge boundary
/// (see ``mergeOTelAttributes(sdkSet:sdkSetKeys:provider:context:)``).
public typealias OTelAttributeProvider =
    (PerformanceSuiteSignalContext) -> [String: AttributeValue]
