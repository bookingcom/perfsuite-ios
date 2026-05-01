//
//  MockTracerProvider.swift
//  PerformanceSuiteOTel-Tests
//
//  Created by Ahmed Nafei on 30/04/2026.
//

import Foundation
import OpenTelemetryApi

/// Test double for `TracerProvider`. Records every `get` call and returns a
/// shared ``MockTracer`` so tests can drill into the spans that were built.
final class MockTracerProvider: TracerProvider {

    struct GetCall: Equatable {
        let instrumentationName: String
        let instrumentationVersion: String?
        let schemaUrl: String?
        let attributes: [String: AttributeValue]?
    }

    private(set) var getCalls: [GetCall] = []
    let tracer = MockTracer()

    func get(
        instrumentationName: String,
        instrumentationVersion: String?,
        schemaUrl: String?,
        attributes: [String: AttributeValue]?
    ) -> any Tracer {
        getCalls.append(
            GetCall(
                instrumentationName: instrumentationName,
                instrumentationVersion: instrumentationVersion,
                schemaUrl: schemaUrl,
                attributes: attributes
            )
        )
        return tracer
    }
}
