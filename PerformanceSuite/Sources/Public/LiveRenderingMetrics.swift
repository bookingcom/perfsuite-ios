//
//  LiveRenderingMetrics.swift
//  PerformanceSuite
//
//  Created by Gleb Tarasov on 20/11/2026.
//

import Foundation

/// Rendering metrics of a live measurement so far, updated by PerformanceSuite on every frame.
/// Lets a live receiver end the measurement on its own with exact metrics. Thread-safe.
public final class LiveRenderingMetrics {

    init(_ metrics: RenderingMetrics) {
        self.metrics = metrics
    }

    public var current: RenderingMetrics {
        lock.lock()
        defer { lock.unlock() }
        return metrics
    }

    func update(_ metrics: RenderingMetrics) {
        lock.lock()
        defer { lock.unlock() }
        self.metrics = metrics
    }

    private let lock = NSLock()
    private var metrics: RenderingMetrics
}
