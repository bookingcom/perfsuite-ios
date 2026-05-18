//
//  MockLogger.swift
//  PerformanceSuiteOTel-Tests
//
//  Created by Ahmed Nafei on 18/05/2026.
//

import Foundation
import OpenTelemetryApi

/// Test double for `Logger`. Returns a fresh ``MockLogRecordBuilder`` per
/// `logRecordBuilder()` call and stores them in `builders` so multi-emission
/// tests can inspect each individually. The most-recent builder is exposed
/// as `lastBuilder` for convenience.
///
/// `eventBuilder(name:)` is required by the deprecated `Logger` protocol
/// surface but is unused by ``OTelLogEmitter`` — the implementation returns
/// a no-op stub builder.
final class MockLogger: Logger {

    private(set) var builders: [MockLogRecordBuilder] = []
    private(set) var eventBuilderNames: [String] = []

    var lastBuilder: MockLogRecordBuilder? { builders.last }

    func logRecordBuilder() -> LogRecordBuilder {
        let builder = MockLogRecordBuilder()
        builders.append(builder)
        return builder
    }

    func eventBuilder(name: String) -> EventBuilder {
        eventBuilderNames.append(name)
        return MockEventBuilder()
    }
}

/// Minimal stub for the deprecated `EventBuilder` API. ``OTelLogEmitter``
/// never calls into this path; the stub exists only to satisfy ``MockLogger``'s
/// `Logger` conformance.
private final class MockEventBuilder: EventBuilder {
    func setData(_ attributes: [String: AttributeValue]) -> Self { self }
}
