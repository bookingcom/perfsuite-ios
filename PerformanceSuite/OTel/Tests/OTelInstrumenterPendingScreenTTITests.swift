//
//  OTelInstrumenterPendingScreenTTITests.swift
//  PerformanceSuiteOTel-Tests
//
//  Created by Ahmed Nafei on 01/10/2026.
//

import OpenTelemetryApi
@testable import PerformanceSuite
import UIKit
import XCTest

#if canImport(PerformanceSuiteOTel)
@testable import PerformanceSuiteOTel
#endif

/// The `screen-tti.pending` span `screenIsBeingCreated()` opens, its adoption by a screen, and its endings.
@available(iOS 16.0, *)
final class OTelInstrumenterPendingScreenTTITests: XCTestCase {

    private enum TestScreen: String {
        case bookingStep1 = "book_1"
    }

    private enum TestFragment: Equatable {
        case header
    }

    private let pinnedNow = Date(timeIntervalSince1970: 1_700_000_000)
    private let callTime = Date(timeIntervalSince1970: 1_699_999_997)
    private var providerContexts: [PerformanceSuiteSignalContext] = []
    private var shouldEmitContexts: [PerformanceSuiteSignalContext] = []

    private func makeInstrumenter(
        provider: MockTracerProvider,
        hostAttributes: [String: AttributeValue] = [:],
        shouldEmit: Bool = true,
        autoTerminationAttribute: (key: String, value: String)? = nil
    ) -> OTelInstrumenter<TestScreen, TestFragment> {
        OTelInstrumenter<TestScreen, TestFragment>(
            screenIdentifier: nil,
            tracerProvider: provider,
            instrumentationName: "perfsuite-ios",
            spanNamePrefix: "bk.app",
            attributeProvider: { [unowned self] context in
                self.providerContexts.append(context)
                return hostAttributes
            },
            shouldEmit: { [unowned self] context in
                self.shouldEmitContexts.append(context)
                return shouldEmit
            },
            autoTerminationAttribute: autoTerminationAttribute,
            now: { [unowned self] in self.pinnedNow }
        )
    }

    // MARK: - Start

    func testPendingStartOpensAnUnnamedSpanAtTheCallWithoutHostCallbacks() throws {
        let provider = MockTracerProvider()
        let instrumenter = makeInstrumenter(
            provider: provider, autoTerminationAttribute: ("emb.auto_termination.code", "user_abandon"))

        let handle = instrumenter.screenTTIPendingMeasurementStarted(at: callTime)

        XCTAssertTrue(handle is OTelSpanContext)
        let builder = try XCTUnwrap(provider.tracer.lastBuilder)
        XCTAssertEqual(builder.spanName, "bk.app.screen-tti.pending")
        XCTAssertEqual(builder.startTime, callTime)
        XCTAssertNil(builder.attributes["screen.name"])
        XCTAssertEqual(builder.attributes["emb.auto_termination.code"]?.stringValue, "user_abandon")
        XCTAssertTrue(try XCTUnwrap(builder.startedSpan).isRecording)
        XCTAssertTrue(providerContexts.isEmpty)
        XCTAssertTrue(shouldEmitContexts.isEmpty)
    }

    // MARK: - Adoption

    func testAdoptionRenamesTheSpanAndTheScreenReportsOnIt() throws {
        let provider = MockTracerProvider()
        let instrumenter = makeInstrumenter(provider: provider)
        let pending = try XCTUnwrap(instrumenter.screenTTIPendingMeasurementStarted(at: callTime))

        let adopted = instrumenter.screenTTIPendingMeasurementAdopted(pending, screen: .bookingStep1)
        instrumenter.screenTTIMeasurementEnded(
            metrics: TTIMetrics(tti: .milliseconds(3_000), ttfr: .milliseconds(40), appStartInfo: .empty, customStart: true),
            screen: .bookingStep1,
            context: adopted
        )

        XCTAssertTrue(adopted === pending)
        XCTAssertEqual(provider.tracer.builders.count, 1, "no second span")
        let span = try XCTUnwrap(provider.tracer.lastBuilder?.startedSpan)
        XCTAssertEqual(span.name, "bk.app.screen-tti.book_1")
        XCTAssertEqual(span.startTime, callTime)
        XCTAssertEqual(span.attributes["screen.name"]?.stringValue, "book_1")
        XCTAssertEqual(span.attributes["screen.tti.ms"]?.intValue, 3_000)
        XCTAssertEqual(span.attributes["screen.tti.custom_start"]?.boolValue, true)
        XCTAssertEqual(span.endCalls, [pinnedNow])
        XCTAssertEqual(span.status, .unset)
    }

    func testAdoptionRunsShouldEmitAndTheProviderOnceWithTheScreen() throws {
        let provider = MockTracerProvider()
        let instrumenter = makeInstrumenter(provider: provider, hostAttributes: ["EXPS0": .string("ok")])
        let pending = try XCTUnwrap(instrumenter.screenTTIPendingMeasurementStarted(at: callTime))

        let adopted = instrumenter.screenTTIPendingMeasurementAdopted(pending, screen: .bookingStep1)
        instrumenter.screenTTIMeasurementEnded(
            metrics: TTIMetrics(tti: .milliseconds(3_000), ttfr: .milliseconds(40), appStartInfo: .empty),
            screen: .bookingStep1,
            context: adopted
        )

        XCTAssertEqual(screenNames(providerContexts), ["book_1"], "one provider call per screen-TTI span")
        XCTAssertEqual(screenNames(shouldEmitContexts), ["book_1"])
        let span = try XCTUnwrap(provider.tracer.lastBuilder?.startedSpan)
        XCTAssertEqual(span.attributes["EXPS0"]?.stringValue, "ok")
    }

    func testHostCannotOverwriteReservedKeysAtAdoption() throws {
        let provider = MockTracerProvider()
        let instrumenter = makeInstrumenter(
            provider: provider,
            hostAttributes: [
                "screen.name": .string("host"),
                "screen.tti.custom_start": .bool(true),
                "emb.auto_termination.code": .string("host"),
            ],
            autoTerminationAttribute: ("emb.auto_termination.code", "user_abandon")
        )
        let pending = try XCTUnwrap(instrumenter.screenTTIPendingMeasurementStarted(at: callTime))

        _ = instrumenter.screenTTIPendingMeasurementAdopted(pending, screen: .bookingStep1)

        let span = try XCTUnwrap(provider.tracer.lastBuilder?.startedSpan)
        XCTAssertEqual(span.attributes["screen.name"]?.stringValue, "book_1")
        XCTAssertNil(span.attributes["screen.tti.custom_start"], "written only when the screen reports")
        XCTAssertEqual(span.attributes["emb.auto_termination.code"]?.stringValue, "user_abandon")
    }

    func testShouldEmitRejectionAtAdoptionEndsTheRenamedSpan() throws {
        let provider = MockTracerProvider()
        let instrumenter = makeInstrumenter(provider: provider, shouldEmit: false)
        let pending = try XCTUnwrap(instrumenter.screenTTIPendingMeasurementStarted(at: callTime))

        let adopted = instrumenter.screenTTIPendingMeasurementAdopted(pending, screen: .bookingStep1)

        XCTAssertNil(adopted)
        let span = try XCTUnwrap(provider.tracer.lastBuilder?.startedSpan)
        XCTAssertEqual(span.name, "bk.app.screen-tti.book_1")
        XCTAssertEqual(span.status, .error(description: "shouldEmit_rejected"))
        XCTAssertEqual(span.endCalls, [pinnedNow])
        XCTAssertTrue(providerContexts.isEmpty)
    }

    func testAdoptingAnEndedPendingSpanStartsTheScreensOwnSpan() throws {
        let provider = MockTracerProvider()
        let instrumenter = makeInstrumenter(provider: provider)
        let pending = try XCTUnwrap(instrumenter.screenTTIPendingMeasurementStarted(at: callTime))
        let pendingSpan = try XCTUnwrap(provider.tracer.lastBuilder?.startedSpan)
        pendingSpan.end(time: callTime)

        let adopted = instrumenter.screenTTIPendingMeasurementAdopted(pending, screen: .bookingStep1)
        instrumenter.screenTTIMeasurementEnded(
            metrics: TTIMetrics(tti: .milliseconds(3_000), ttfr: .milliseconds(40), appStartInfo: .empty),
            screen: .bookingStep1,
            context: adopted
        )

        XCTAssertFalse(adopted === pending)
        XCTAssertEqual(provider.tracer.builders.map(\.spanName), ["bk.app.screen-tti.pending", "bk.app.screen-tti.book_1"])
        let span = try XCTUnwrap(provider.tracer.lastBuilder?.startedSpan)
        XCTAssertEqual(span.attributes["screen.tti.ms"]?.intValue, 3_000)
        XCTAssertEqual(pendingSpan.name, "bk.app.screen-tti.pending")
        XCTAssertEqual(pendingSpan.endCalls.count, 1)
    }

    // MARK: - Endings

    func testEachEndReasonClosesThePendingSpanWithItsStatus() throws {
        let expected: [(PendingScreenTTIEndReason, String)] = [
            (.creationCancelled, "screen_creation_cancelled"),
            (.superseded, "superseded"),
            (.notAdopted, "not_adopted"),
            (.abandoned, "abandoned"),
        ]
        for (reason, description) in expected {
            let provider = MockTracerProvider()
            let instrumenter = makeInstrumenter(provider: provider)
            let pending = try XCTUnwrap(instrumenter.screenTTIPendingMeasurementStarted(at: callTime))

            instrumenter.screenTTIPendingMeasurementEnded(pending, reason: reason)

            let span = try XCTUnwrap(provider.tracer.lastBuilder?.startedSpan)
            XCTAssertEqual(span.name, "bk.app.screen-tti.pending", "\(reason)")
            XCTAssertEqual(span.status, .error(description: description), "\(reason)")
            XCTAssertEqual(span.endCalls, [pinnedNow], "\(reason)")
        }
        XCTAssertTrue(providerContexts.isEmpty, "an unadopted span gets no host attributes")
        XCTAssertTrue(shouldEmitContexts.isEmpty)
    }

    func testEndingAnAlreadyEndedPendingSpanDoesNothing() throws {
        let provider = MockTracerProvider()
        let instrumenter = makeInstrumenter(provider: provider)
        let pending = try XCTUnwrap(instrumenter.screenTTIPendingMeasurementStarted(at: callTime))
        pending.cancel()

        instrumenter.screenTTIPendingMeasurementEnded(pending, reason: .abandoned)

        let span = try XCTUnwrap(provider.tracer.lastBuilder?.startedSpan)
        XCTAssertEqual(span.status, .error(description: "measurement_cancelled"))
        XCTAssertEqual(span.endCalls.count, 1)
    }

    // MARK: - custom_start on screens that open their own span

    func testCustomStartIsWrittenOnEveryReportedScreenTTISpan() throws {
        for customStart in [false, true] {
            let provider = MockTracerProvider()
            let instrumenter = makeInstrumenter(provider: provider)
            let context = instrumenter.screenTTIMeasurementStarted(screen: .bookingStep1)

            instrumenter.screenTTIMeasurementEnded(
                metrics: TTIMetrics(
                    tti: .milliseconds(500), ttfr: .milliseconds(40), appStartInfo: .empty, customStart: customStart),
                screen: .bookingStep1,
                context: context
            )

            let span = try XCTUnwrap(provider.tracer.lastBuilder?.startedSpan)
            XCTAssertEqual(span.attributes["screen.tti.custom_start"]?.boolValue, customStart)
        }
    }

    private func screenNames(_ contexts: [PerformanceSuiteSignalContext]) -> [String] {
        contexts.compactMap {
            if case .screenTTI(let screen) = $0 { return screen.screenName }
            return nil
        }
    }
}
