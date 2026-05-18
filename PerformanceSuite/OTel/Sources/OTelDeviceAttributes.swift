//
//  OTelDeviceAttributes.swift
//  PerformanceSuiteOTel
//
//  Created by Ahmed Nafei on 18/05/2026.
//

import Foundation
import OpenTelemetryApi
import UIKit

/// Adds the device / OS semantic-convention attributes (`os.name`,
/// `os.version`, `device.model`) onto the supplied attribute dictionary.
/// Used by ``OTelSpanEmitter`` when emitting startup and watchdog-termination
/// spans, where the device / OS context is part of the recorded telemetry.
///
/// Extracted from ``OTelSpanEmitter`` so the emitter stays under SwiftLint's
/// type-body / file-length thresholds.
func addOTelDeviceAttributes(to attributes: inout [String: AttributeValue]) {
    let attrs = OTelSemanticConventions.Attribute.self
    attributes[attrs.osName] = .string(OTelSemanticConventions.osNameValue)
    attributes[attrs.osVersion] = .string(UIDevice.current.systemVersion)
    attributes[attrs.deviceModel] = .string(deviceModelCode())
}

/// Hardware model code such as `"iPhone15,3"` (vs. the marketing name
/// `UIDevice.current.model` returns, which is just `"iPhone"`). Pulled from
/// `utsname.machine`. Falls back to `UIDevice.current.model` if the syscall
/// is somehow unavailable.
private func deviceModelCode() -> String {
    var systemInfo = utsname()
    guard uname(&systemInfo) == 0 else {
        return UIDevice.current.model
    }
    let machineMirror = Mirror(reflecting: systemInfo.machine)
    let identifier = machineMirror.children.reduce(into: "") { acc, element in
        guard let value = element.value as? Int8, value != 0 else { return }
        acc.append(Character(UnicodeScalar(UInt8(value))))
    }
    return identifier.isEmpty ? UIDevice.current.model : identifier
}

/// Physical memory in MB, used as the SDK value for `device.ram.mb`.
func otelPhysicalMemoryMb() -> Int {
    Int(ProcessInfo.processInfo.physicalMemory / (1024 * 1024))
}

/// Maps `UIApplication.State` to its semantic-convention string. `nil` and
/// any future case map to ``OTelSemanticConventions/AppState/unknown``.
func otelAppStateString(from applicationState: UIApplication.State?) -> String {
    guard let applicationState else {
        return OTelSemanticConventions.AppState.unknown
    }
    switch applicationState {
    case .active:
        return OTelSemanticConventions.AppState.active
    case .inactive:
        return OTelSemanticConventions.AppState.inactive
    case .background:
        return OTelSemanticConventions.AppState.background
    @unknown default:
        return OTelSemanticConventions.AppState.unknown
    }
}
