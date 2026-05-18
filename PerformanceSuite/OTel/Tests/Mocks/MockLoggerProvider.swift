//
//  MockLoggerProvider.swift
//  PerformanceSuiteOTel-Tests
//
//  Created by Ahmed Nafei on 18/05/2026.
//

import Foundation
import OpenTelemetryApi

/// Test double for `LoggerProvider`. Records every
/// `get(instrumentationScopeName:)` invocation so tests can verify lazy
/// resolution behaviour, and returns the same shared ``MockLogger`` so
/// repeated emissions land on builders observable from a single place.
///
/// `loggerBuilder(instrumentationScopeName:)` is required by the
/// `LoggerProvider` protocol but is unused by ``OTelLogEmitter``; the
/// implementation returns a no-op stub builder whose `build()` produces the
/// same shared ``MockLogger``.
final class MockLoggerProvider: LoggerProvider {

    let logger = MockLogger()

    private(set) var getCalls: [String] = []

    func get(instrumentationScopeName: String) -> Logger {
        getCalls.append(instrumentationScopeName)
        return logger
    }

    func loggerBuilder(instrumentationScopeName: String) -> LoggerBuilder {
        getCalls.append(instrumentationScopeName)
        return MockLoggerBuilder(logger: logger)
    }
}

/// Minimal stub for `LoggerBuilder`. ``OTelLogEmitter`` only calls
/// `LoggerProvider.get(instrumentationScopeName:)`, so this builder exists
/// only to satisfy the `LoggerProvider` protocol's required surface. Every
/// chainable setter is a no-op; `build()` returns the shared mock logger.
private final class MockLoggerBuilder: LoggerBuilder {
    private let logger: MockLogger

    init(logger: MockLogger) {
        self.logger = logger
    }

    func setEventDomain(_ eventDomain: String) -> Self { self }
    func setSchemaUrl(_ schemaUrl: String) -> Self { self }
    func setInstrumentationVersion(_ instrumentationVersion: String) -> Self { self }
    func setIncludeTraceContext(_ includeTraceContext: Bool) -> Self { self }
    func setAttributes(_ attributes: [String: AttributeValue]) -> Self { self }

    func build() -> Logger { logger }
}
