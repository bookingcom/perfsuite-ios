//
//  MockLogRecordBuilder.swift
//  PerformanceSuiteOTel-Tests
//
//  Created by Ahmed Nafei on 18/05/2026.
//

import Foundation
import OpenTelemetryApi

/// Test double for `LogRecordBuilder`. Captures every chainable setter, then
/// records an `emit()` invocation. Most tests inspect the builder for
/// severity / body / attributes / timestamps after the emitter has finished.
final class MockLogRecordBuilder: LogRecordBuilder {

    private(set) var severity: Severity?
    private(set) var body: AttributeValue?
    private(set) var timestamp: Date?
    private(set) var observedTimestamp: Date?
    private(set) var spanContext: SpanContext?
    private(set) var attributes: [String: AttributeValue] = [:]
    private(set) var eventName: String?
    private(set) var emitted = false

    func setTimestamp(_ timestamp: Date) -> Self {
        self.timestamp = timestamp
        return self
    }

    func setObservedTimestamp(_ observed: Date) -> Self {
        self.observedTimestamp = observed
        return self
    }

    func setSpanContext(_ context: SpanContext) -> Self {
        self.spanContext = context
        return self
    }

    func setSeverity(_ severity: Severity) -> Self {
        self.severity = severity
        return self
    }

    func setBody(_ body: AttributeValue) -> Self {
        self.body = body
        return self
    }

    func setAttributes(_ attributes: [String: AttributeValue]) -> Self {
        self.attributes = attributes
        return self
    }

    func setEventName(_ eventName: String) -> Self {
        self.eventName = eventName
        return self
    }

    func emit() {
        emitted = true
    }
}
