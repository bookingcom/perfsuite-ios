//
//  AppRenderingSessionAccumulator.swift
//  PerformanceSuiteOTel
//
//  Created by Ahmed Nafei on 09/06/2026.
//

import Foundation
import UIKit

#if canImport(PerformanceSuiteOTel)
import PerformanceSuite
#endif

/// Accumulates `RenderingMetrics` across the SDK's throttled
/// `appRenderingMetricsReceived(metrics:)` callbacks and emits one OTel span
/// per app-foreground session.
///
/// `sessionStartedAt` is seeded from ``PerformanceMonitoring/processStartTime``
/// at init, so the first session is anchored on the actual process launch
/// regardless of when the host calls `enable(...)`. Subsequent sessions are
/// anchored on `didBecomeActive` (after `didEnterBackground` clears the
/// previous session's anchor).
///
/// Lifetime mirrors the owning ``OTelInstrumenter``: subscriptions are
/// installed at init and torn down in `deinit`. State (the in-flight
/// `sessionStartedAt` timestamp and the running `accumulated` metrics) is
/// guarded by a private lock — `UIApplication` notifications by default arrive
/// on the posting thread (main thread for the lifecycle notifications), while
/// `appRenderingMetricsReceived(metrics:)` runs on `PerformanceMonitoring`'s
/// background consumer queue, so the accumulator interleaves across two
/// threads and needs synchronisation.
///
/// The session boundary is intentionally `didEnterBackground`, not
/// `willResignActive` — the latter fires for transient interruptions
/// (control-centre swipes, incoming-call banners, app-switcher previews) which
/// would split a single user session into many tiny spans. `didEnterBackground`
/// only fires for genuine backgrounding.
final class AppRenderingSessionAccumulator {

    private let emitter: OTelSpanEmitter
    private let notificationCenter: NotificationCenter
    private let now: () -> Date

    private let lock = NSLock()
    /// Wall-clock anchor for the in-flight session. Seeded from
    /// `PerformanceMonitoring.processStartTime` at init; reset to `nil` on
    /// `didEnterBackground`; set to `Date()` on `didBecomeActive` when nil.
    private var sessionStartedAt: Date?
    /// Sum of every `RenderingMetrics` chunk that arrived during the
    /// in-flight session. Reset to `.zero` on every `didEnterBackground`.
    private var accumulated: RenderingMetrics = .zero

    private var didBecomeActiveObserver: NSObjectProtocol?
    private var didEnterBackgroundObserver: NSObjectProtocol?

    init(
        emitter: OTelSpanEmitter,
        notificationCenter: NotificationCenter = .default,
        sessionStartedAt: Date = PerformanceMonitoring.processStartTime,
        now: @escaping () -> Date = Date.init
    ) {
        self.emitter = emitter
        self.notificationCenter = notificationCenter
        self.now = now
        self.sessionStartedAt = sessionStartedAt
        self.subscribe()
    }

    deinit {
        if let observer = didBecomeActiveObserver {
            notificationCenter.removeObserver(observer)
        }
        if let observer = didEnterBackgroundObserver {
            notificationCenter.removeObserver(observer)
        }
    }

    // MARK: - Public hook

    /// Called by ``OTelInstrumenter`` from its
    /// ``AppRenderingMetricsReceiver/appRenderingMetricsReceived(metrics:)``
    /// implementation. Adds the chunk's counters to the running session
    /// accumulator.
    func appRenderingMetricsReceived(metrics: RenderingMetrics) {
        lock.lock()
        defer { lock.unlock() }
        accumulated = accumulated + metrics
    }

    // MARK: - Lifecycle handlers

    private func subscribe() {
        didBecomeActiveObserver = notificationCenter.addObserver(
            forName: UIApplication.didBecomeActiveNotification,
            object: nil,
            queue: nil
        ) { [weak self] _ in
            self?.handleDidBecomeActive()
        }
        didEnterBackgroundObserver = notificationCenter.addObserver(
            forName: UIApplication.didEnterBackgroundNotification,
            object: nil,
            queue: nil
        ) { [weak self] _ in
            self?.handleDidEnterBackground()
        }
    }

    private func handleDidBecomeActive() {
        let timestamp = now()
        lock.lock()
        defer { lock.unlock() }
        if sessionStartedAt == nil {
            sessionStartedAt = timestamp
        }
    }

    private func handleDidEnterBackground() {
        let endedAt = now()

        let pending: (start: Date, metrics: RenderingMetrics)? = {
            lock.lock()
            defer { lock.unlock() }
            guard let started = sessionStartedAt else {
                accumulated = .zero
                return nil
            }
            let metricsSnapshot = accumulated
            sessionStartedAt = nil
            accumulated = .zero
            return (started, metricsSnapshot)
        }()

        guard let pending else { return }
        guard pending.metrics != .zero else { return }

        emitter.emitAppSessionRenderingSpan(
            metrics: pending.metrics,
            sessionStartedAt: pending.start,
            sessionEndedAt: endedAt
        )
    }
}
