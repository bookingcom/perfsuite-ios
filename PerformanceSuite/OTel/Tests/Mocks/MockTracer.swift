//
//  MockTracer.swift
//  PerformanceSuiteOTel-Tests
//
//  Created by Ahmed Nafei on 30/04/2026.
//

import Foundation
import OpenTelemetryApi

/// Test double for `Tracer`. Returns a fresh ``MockSpanBuilder`` per call and
/// keeps every builder around so tests can assert on the resulting spans
/// regardless of construction order.
final class MockTracer: Tracer {

    private(set) var builders: [MockSpanBuilder] = []

    /// Convenience accessor — most tests look at "the most recently built
    /// span" rather than iterating through every emission.
    var lastBuilder: MockSpanBuilder? { builders.last }

    func spanBuilder(spanName: String) -> SpanBuilder {
        let builder = MockSpanBuilder(spanName: spanName)
        builders.append(builder)
        return builder
    }
}
