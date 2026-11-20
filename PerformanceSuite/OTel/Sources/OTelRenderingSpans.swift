//
//  OTelRenderingSpans.swift
//  PerformanceSuiteOTel
//
//  Created by Gleb Tarasov on 20/11/2026.
//

import Foundation

#if canImport(PerformanceSuiteOTel)
import PerformanceSuite
#endif

/// Open screen-rendering spans with the latest metrics reported for each, so ``OTelInstrumenter`` can end them
/// on its own on `willResignActive`. Called from any thread; `lock` is held only by this type.
final class OTelRenderingSpans {

    private struct Entry {
        weak var context: OTelSpanContext?
        var metrics: RenderingMetrics?
    }

    private let lock = NSLock()
    private var entries: [ObjectIdentifier: Entry] = [:]

    func add(_ context: OTelSpanContext) {
        lock.lock()
        defer { lock.unlock() }
        // Cancelled spans are never removed explicitly, so drop the released ones here.
        entries = entries.filter { $0.value.context != nil }
        entries[ObjectIdentifier(context)] = Entry(context: context)
    }

    /// Returns `false` if the span was already ended by `removeAll()`.
    func update(_ context: OTelSpanContext, metrics: RenderingMetrics) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard entries[ObjectIdentifier(context)] != nil else {
            return false
        }
        entries[ObjectIdentifier(context)]?.metrics = metrics
        return true
    }

    /// Returns `false` if the span was already ended by `removeAll()`.
    func remove(_ context: OTelSpanContext) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return entries.removeValue(forKey: ObjectIdentifier(context)) != nil
    }

    func removeAll() -> [(context: OTelSpanContext, metrics: RenderingMetrics?)] {
        lock.lock()
        defer { lock.unlock() }
        let open = entries.values.compactMap { entry in
            entry.context.map { (context: $0, metrics: entry.metrics) }
        }
        entries = [:]
        return open
    }
}
