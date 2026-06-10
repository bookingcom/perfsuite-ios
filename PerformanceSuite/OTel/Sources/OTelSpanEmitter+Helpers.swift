//
//  OTelSpanEmitter+Helpers.swift
//  PerformanceSuiteOTel
//
//  Created by Ahmed Nafei on 09/06/2026.
//

import Foundation
import OpenTelemetryApi

/// Internal helper types for ``OTelSpanEmitter``. Lives in a sibling file to
/// keep the main emitter under SwiftLint's length limits.
extension OTelSpanEmitter {

    /// Bundles the SDK-set attributes and the SDK-reserved key set for a
    /// single signal emission.
    struct SDKAttributeSet {
        var values: [String: AttributeValue]
        let reservedKeys: Set<String>
    }

    /// Bundles the three attribute keys that vary between screen TTI and
    /// fragment TTI emission, plus exposes them as a `Set<String>` for the
    /// merge guard.
    struct TTIAttributeKeys {
        let nameKey: String
        let ttiKey: String
        let ttfrKey: String

        var allKeys: Set<String> { [nameKey, ttiKey, ttfrKey] }
    }
}
