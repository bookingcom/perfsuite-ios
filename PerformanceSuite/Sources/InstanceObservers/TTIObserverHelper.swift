//
//  TTIObserverHelper.swift
//  PerformanceSuite
//
//  Created by Ahmed Nafei on 01/10/2026.
//

import UIKit

/// Type-erased access to the live TTI receiver, for the pending measurement that `screenIsBeingCreated()` opens.
/// A class, so a queued step can tell whether `disable()` replaced it in the meantime.
final class PendingScreenTTIHook {
    let start: (Date) -> (any MeasurementHandle)?
    let end: (any MeasurementHandle, PendingScreenTTIEndReason) -> Void

    init(
        start: @escaping (Date) -> (any MeasurementHandle)?,
        end: @escaping (any MeasurementHandle, PendingScreenTTIEndReason) -> Void
    ) {
        self.start = start
        self.end = end
    }

    /// `nil` unless the screen-TTI receiver is a ``LiveTTIMetricsReceiver``.
    static func make(config: Config) -> PendingScreenTTIHook? {
        guard let screenTTIReceiver = config.screenTTIReceiver else { return nil }
        return make(metricsReceiver: screenTTIReceiver)
    }

    private static func make<T: TTIMetricsReceiver>(metricsReceiver: T) -> PendingScreenTTIHook? {
        guard #available(iOS 16.0, *), let live = metricsReceiver as? any LiveTTIMetricsReceiver<T.ScreenIdentifier> else {
            return nil
        }
        return PendingScreenTTIHook(
            start: { live.screenTTIPendingMeasurementStarted(at: $0) },
            end: { live.screenTTIPendingMeasurementEnded($0, reason: $1) }
        )
    }
}

/// Non-generic helper for generic `TTIObserver`. To put all the static methods and vars there.
final class TTIObserverHelper {
    static var upcomingCustomCreationTime: DispatchTime?
    static func startCustomCreationTime(timeProvider: TimeProvider = defaultTimeProvider) {
        let now = timeProvider.now()
        // Opened on the caller's thread, so a request the caller starts next can already see it.
        let hook = installedHook
        let handle = hook?.start(Date())
        PerformanceMonitoring.queue.async {
            upcomingCustomCreationTime = now
            if let hook {
                storePendingMeasurement(handle, openedBy: hook, startTime: now)
            }
        }
    }

    static func clearCustomCreationTime() {
        PerformanceMonitoring.queue.async {
            upcomingCustomCreationTime = nil
            endPendingMeasurement(reason: .creationCancelled)
        }
    }

    static let identifier: AnyObject = NSObject()

    // MARK: - Pending measurement
    //
    // Read and written only on `PerformanceMonitoring.queue`, except `installedHook`.

    static let defaultPendingMaxAge: DispatchTimeInterval = .seconds(60)

    /// How long a pending measurement waits for a screen to adopt it. Changed only by tests.
    static var pendingMaxAge = defaultPendingMaxAge

    /// The hook as the queue sees it; `installedHook` is what callers of `screenIsBeingCreated()` see.
    private static var hook: PendingScreenTTIHook?
    private static var pending: PendingMeasurement?

    private static let hookLock = NSLock()
    private static var _installedHook: PendingScreenTTIHook?

    static func installPendingHook(_ newHook: PendingScreenTTIHook?) {
        guard let newHook else { return }
        installedHook = newHook
        PerformanceMonitoring.queue.async {
            hook = newHook
        }
    }

    static func uninstallPendingHook() {
        installedHook = nil
        PerformanceMonitoring.queue.async {
            // A re-enabled monitor must not adopt a measurement opened for the previous receiver.
            takePending()?.handle.cancel()
            hook = nil
        }
    }

    static func endPendingMeasurement(reason: PendingScreenTTIEndReason) {
        dispatchPrecondition(condition: .onQueue(PerformanceMonitoring.queue))
        guard let measurement = takePending() else { return }
        measurement.end(measurement.handle, reason)
    }

    /// Hands the pending measurement to the screen that starts measuring next. One older than `pendingMaxAge`
    /// ends `abandoned` instead.
    static func adoptPendingMeasurement(now: DispatchTime) -> (any MeasurementHandle)? {
        dispatchPrecondition(condition: .onQueue(PerformanceMonitoring.queue))
        guard let measurement = takePending() else { return nil }
        guard now <= measurement.startTime.advanced(by: pendingMaxAge) else {
            measurement.end(measurement.handle, .abandoned)
            return nil
        }
        return measurement.handle
    }

    static func resetForTests() {
        installedHook = nil
        PerformanceMonitoring.runOnQueue {
            takePending()
            hook = nil
            upcomingCustomCreationTime = nil
            pendingMaxAge = defaultPendingMaxAge
        }
    }

    /// The queued half of `startCustomCreationTime`: in queue order with the screens' lifecycle callbacks, so only a
    /// screen that starts measuring after the call can adopt it.
    private static func storePendingMeasurement(
        _ handle: (any MeasurementHandle)?,
        openedBy openingHook: PendingScreenTTIHook,
        startTime: DispatchTime
    ) {
        dispatchPrecondition(condition: .onQueue(PerformanceMonitoring.queue))
        guard openingHook === hook else {
            // `disable()` ran between the call and this step: the measurement belongs to the previous receiver.
            handle?.cancel()
            return
        }
        // The anchor moved to this call, so the measurement of an earlier call no longer matches it.
        if let previous = takePending() {
            previous.end(previous.handle, .superseded)
        }
        guard let handle else { return }
        let measurement = PendingMeasurement(handle: handle, startTime: startTime, end: openingHook.end)
        let expiry = DispatchWorkItem { [weak measurement] in
            guard let measurement, pending === measurement else { return }
            endPendingMeasurement(reason: .abandoned)
        }
        measurement.expiry = expiry
        pending = measurement
        PerformanceMonitoring.queue.asyncAfter(deadline: .now() + pendingMaxAge, execute: expiry)
    }

    @discardableResult
    private static func takePending() -> PendingMeasurement? {
        guard let measurement = pending else { return nil }
        pending = nil
        measurement.expiry?.cancel()
        return measurement
    }

    private static var installedHook: PendingScreenTTIHook? {
        get {
            hookLock.lock()
            defer { hookLock.unlock() }
            return _installedHook
        }
        set {
            hookLock.lock()
            _installedHook = newValue
            hookLock.unlock()
        }
    }
}

/// The measurement `screenIsBeingCreated()` opened, waiting for a screen to adopt it.
private final class PendingMeasurement {
    let handle: any MeasurementHandle
    let startTime: DispatchTime
    let end: (any MeasurementHandle, PendingScreenTTIEndReason) -> Void
    var expiry: DispatchWorkItem?

    init(
        handle: any MeasurementHandle,
        startTime: DispatchTime,
        end: @escaping (any MeasurementHandle, PendingScreenTTIEndReason) -> Void
    ) {
        self.handle = handle
        self.startTime = startTime
        self.end = end
    }
}
