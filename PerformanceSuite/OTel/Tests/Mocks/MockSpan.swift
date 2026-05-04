//
//  MockSpan.swift
//  PerformanceSuiteOTel-Tests
//
//  Created by Ahmed Nafei on 30/04/2026.
//

import Foundation
import OpenTelemetryApi

/// Captured `addEvent` invocation, swapped for what would otherwise be a
/// `(name, attributes, timestamp)` 3-tuple inside ``MockSpan``. Wrapping it in
/// a struct keeps SwiftLint's `large_tuple` rule happy and makes assertions in
/// future tests (when needed) read more naturally than tuple-element access.
struct RecordedEvent {
    let name: String
    let attributes: [String: AttributeValue]
    let timestamp: Date?
}

/// Test double for `Span`. Captures the attributes that were set at build time
/// (passed in by ``MockSpanBuilder``) plus any attributes added after start,
/// and records every `end()` / `end(time:)` invocation. Other protocol surface
/// (`addEvent`, `recordException`, status / name mutation) is implemented as
/// no-op-but-recordable for completeness — none of the current tests assert
/// against those, but having the surface stops the compiler from rejecting
/// conformance and avoids surprises if future tests reach for them.
final class MockSpan: Span {

    // MARK: - SpanBase requirements

    var kind: SpanKind
    var context: SpanContext
    var isRecording: Bool = true
    var status: Status = .unset
    var name: String

    // MARK: - Recording state

    let startTime: Date?
    private(set) var endCalls: [Date] = []
    private(set) var attributes: [String: AttributeValue]
    private(set) var events: [RecordedEvent] = []

    /// `true` after any flavour of `end` is called.
    var ended: Bool { !endCalls.isEmpty }

    /// The first explicit end timestamp seen, if any. `end()` (no time) records
    /// the value `MockSpan.endWithoutExplicitTimeMarker`.
    var firstEndTime: Date? { endCalls.first }

    static let endWithoutExplicitTimeMarker = Date.distantPast

    init(name: String, kind: SpanKind, startTime: Date?, attributes: [String: AttributeValue]) {
        self.name = name
        self.kind = kind
        self.startTime = startTime
        self.attributes = attributes
        // A default-init `SpanContext` is invalid (`isValid == false`) and that
        // is fine for our test purposes — nothing in the emitter under test
        // reads it. Using a random one would also work but invalid is cheaper.
        self.context = SpanContext.create(
            traceId: TraceId(),
            spanId: SpanId(),
            traceFlags: TraceFlags(),
            traceState: TraceState()
        )
    }

    // MARK: - Attributes

    func setAttribute(key: String, value: AttributeValue?) {
        if let value {
            attributes[key] = value
        } else {
            attributes.removeValue(forKey: key)
        }
    }

    func setAttributes(_ attributes: [String: AttributeValue]) {
        self.attributes.merge(attributes) { _, new in new }
    }

    // MARK: - Events

    func addEvent(name: String) {
        events.append(RecordedEvent(name: name, attributes: [:], timestamp: nil))
    }

    func addEvent(name: String, timestamp: Date) {
        events.append(RecordedEvent(name: name, attributes: [:], timestamp: timestamp))
    }

    func addEvent(name: String, attributes: [String: AttributeValue]) {
        events.append(RecordedEvent(name: name, attributes: attributes, timestamp: nil))
    }

    func addEvent(name: String, attributes: [String: AttributeValue], timestamp: Date) {
        events.append(RecordedEvent(name: name, attributes: attributes, timestamp: timestamp))
    }

    // MARK: - Exception recording (no-op stubs)

    func recordException(_ exception: SpanException) {}
    func recordException(_ exception: SpanException, timestamp: Date) {}
    func recordException(_ exception: SpanException, attributes: [String: AttributeValue]) {}
    func recordException(_ exception: SpanException, attributes: [String: AttributeValue], timestamp: Date) {}

    // MARK: - End

    func end() {
        endCalls.append(MockSpan.endWithoutExplicitTimeMarker)
        isRecording = false
    }

    func end(time: Date) {
        endCalls.append(time)
        isRecording = false
    }

    // MARK: - CustomStringConvertible

    var description: String { "MockSpan(name=\(name))" }
}

// MARK: - AttributeValue convenience accessors for tests

extension AttributeValue {
    /// Returns the `Int` value if this attribute is an `.int(...)`. Tests use
    /// this to assert numeric attributes without pattern-matching at every
    /// call site.
    var intValue: Int? {
        if case let .int(value) = self {
            return value
        }
        return nil
    }

    var stringValue: String? {
        if case let .string(value) = self {
            return value
        }
        return nil
    }

    var boolValue: Bool? {
        if case let .bool(value) = self {
            return value
        }
        return nil
    }

    var doubleValue: Double? {
        if case let .double(value) = self {
            return value
        }
        return nil
    }
}
