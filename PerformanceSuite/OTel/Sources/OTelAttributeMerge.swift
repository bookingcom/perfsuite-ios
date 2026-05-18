//
//  OTelAttributeMerge.swift
//  PerformanceSuiteOTel
//
//  Created by Ahmed Nafei on 18/05/2026.
//

import Foundation
import OpenTelemetryApi

/// Merges SDK-set semantic-convention attributes with host-supplied attributes
/// from an ``OTelAttributeProvider``, ensuring SDK keys are never overwritten.
///
/// The function is shared by ``OTelSpanEmitter`` (every span emission) and by
/// ``OTelLogEmitter`` (the view-controller leak log record), so the SDK-key
/// guard is implemented exactly once and exercised uniformly across spans and
/// log records.
///
/// - Parameters:
///   - sdkSet: Attributes the SDK actually set for this emission. May be a
///     subset of `sdkSetKeys` (some attributes are conditional on the metric
///     value being present — e.g. `app.startup.main_time.ms` is set only when
///     `data.mainTime != nil`).
///   - sdkSetKeys: The full universe of attribute keys the SDK reserves for
///     this signal kind. Host attributes matching any of these keys are
///     dropped so SDK semantics can't be overwritten by host code.
///   - provider: The host's enrichment closure. May be `nil`, in which case
///     `sdkSet` is returned unchanged.
///   - context: The signal context handed to `provider`. Same enum the host
///     pattern-matches on in its closure.
/// - Returns: `sdkSet` ∪ `provider(context).filtered(by: sdkSetKeys)`. SDK
///   values win on collision (defensively — `sdkSetKeys` already protects).
func mergeOTelAttributes(
    sdkSet: [String: AttributeValue],
    sdkSetKeys: Set<String>,
    provider: OTelAttributeProvider?,
    context: PerformanceSuiteSignalContext
) -> [String: AttributeValue] {
    guard let provider else { return sdkSet }
    let hostAttributes = provider(context).filter { !sdkSetKeys.contains($0.key) }
    return sdkSet.merging(hostAttributes) { sdkValue, _ in sdkValue }
}
