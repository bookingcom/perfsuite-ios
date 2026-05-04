//
//  MockSpanBuilder.swift
//  PerformanceSuiteOTel-Tests
//
//  Created by Ahmed Nafei on 30/04/2026.
//

import Foundation
import OpenTelemetryApi

/// Test double for `SpanBuilder`. Captures every chainable setter (start time,
/// attributes, span kind, parent mode), then hands a captured ``MockSpan`` to
/// `startSpan`. Most tests inspect the builder for attribute values and the
/// span for `end(time:)` invocations.
final class MockSpanBuilder: SpanBuilder {

    enum ParentMode: Equatable {
        case unset
        case noParent
        case parentSpanReference
        case parentContextReference
    }

    let spanName: String

    private(set) var startTime: Date?
    private(set) var spanKind: SpanKind?
    private(set) var parentMode: ParentMode = .unset
    private(set) var attributes: [String: AttributeValue] = [:]
    private(set) var startedSpan: MockSpan?

    init(spanName: String) {
        self.spanName = spanName
    }

    // MARK: - Parent / linking

    @discardableResult
    func setParent(_ parent: any Span) -> Self {
        parentMode = .parentSpanReference
        return self
    }

    @discardableResult
    func setParent(_ parent: SpanContext) -> Self {
        parentMode = .parentContextReference
        return self
    }

    @discardableResult
    func setNoParent() -> Self {
        parentMode = .noParent
        return self
    }

    @discardableResult
    func addLink(spanContext: SpanContext) -> Self { self }

    @discardableResult
    func addLink(spanContext: SpanContext, attributes: [String: AttributeValue]) -> Self { self }

    // MARK: - Attributes

    @discardableResult
    func setAttribute(key: String, value: AttributeValue) -> Self {
        attributes[key] = value
        return self
    }

    // MARK: - Span kind / start time

    @discardableResult
    func setSpanKind(spanKind: SpanKind) -> Self {
        self.spanKind = spanKind
        return self
    }

    @discardableResult
    func setStartTime(time: Date) -> Self {
        startTime = time
        return self
    }

    // MARK: - Active

    @discardableResult
    func setActive(_ active: Bool) -> Self { self }

    // MARK: - Start

    func startSpan() -> any Span {
        let span = MockSpan(name: spanName, kind: spanKind ?? .internal, startTime: startTime, attributes: attributes)
        startedSpan = span
        return span
    }

    // MARK: - Active-span helpers (no defaults exist on the protocol)

    func withActiveSpan<T>(_ operation: (any SpanBase) throws -> T) rethrows -> T {
        let span = startSpan()
        defer { span.end() }
        return try operation(span)
    }

    @available(iOS 13.0, *)
    func withActiveSpan<T>(_ operation: (any SpanBase) async throws -> T) async rethrows -> T {
        let span = startSpan()
        defer { span.end() }
        return try await operation(span)
    }
}
