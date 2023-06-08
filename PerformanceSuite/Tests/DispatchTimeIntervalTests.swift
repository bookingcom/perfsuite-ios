//
//  DispatchTimeIntervalTests.swift
//  PerformanceSuite
//
//  Created by Gleb Tarasov on 07/07/2021.
//

import XCTest

@testable import PerformanceSuite

class DispatchTimeIntervalTests: XCTestCase {

    func testTimeInterval() {
        XCTAssertEqual(DispatchTimeInterval.nanoseconds(6).timeInterval, Double(6) / 1000_000_000)
        XCTAssertEqual(DispatchTimeInterval.nanoseconds(1000).timeInterval, Double(1) / 1000_000)
        XCTAssertEqual(DispatchTimeInterval.microseconds(28).timeInterval, 0.000028)
        XCTAssertEqual(DispatchTimeInterval.milliseconds(10).timeInterval, 0.01)
        XCTAssertEqual(DispatchTimeInterval.milliseconds(17).timeInterval, 0.017)
        XCTAssertEqual(DispatchTimeInterval.seconds(10).timeInterval, 10)
        XCTAssertNil(DispatchTimeInterval.never.timeInterval)
    }

    func testTimeIntervalInitializer() {
        XCTAssertEqual(DispatchTimeInterval.timeInterval(Double(6) / 1000_000_000), .nanoseconds(6))
        XCTAssertEqual(DispatchTimeInterval.timeInterval(Double(6) / 1000_000), .microseconds(6))
        XCTAssertEqual(DispatchTimeInterval.timeInterval(Double(6) / 1000), .milliseconds(6))
        XCTAssertEqual(DispatchTimeInterval.timeInterval(0.01), .milliseconds(10))
        XCTAssertEqual(DispatchTimeInterval.timeInterval(0.017), .milliseconds(17))
        XCTAssertEqual(DispatchTimeInterval.timeInterval(10), .seconds(10))
        XCTAssertEqual(DispatchTimeInterval.timeInterval(1_000_000_004), .seconds(1_000_000_004))
        XCTAssertEqual(DispatchTimeInterval.timeInterval(1_912_912_412_241_952_000), .seconds(1_912_912_412_241_952_000))
        XCTAssertEqual(DispatchTimeInterval.timeInterval(0.14400000000000002), .milliseconds(144))
    }

    func testSeconds() {
        XCTAssertEqual(DispatchTimeInterval.nanoseconds(6).seconds, 0)
        XCTAssertEqual(DispatchTimeInterval.nanoseconds(1000).seconds, 0)
        XCTAssertEqual(DispatchTimeInterval.nanoseconds(1_000_000_004).seconds, 1)
        XCTAssertEqual(DispatchTimeInterval.microseconds(28).seconds, 0)
        XCTAssertEqual(DispatchTimeInterval.microseconds(28_999_111).seconds, 28)
        XCTAssertEqual(DispatchTimeInterval.milliseconds(10).seconds, 0)
        XCTAssertEqual(DispatchTimeInterval.milliseconds(1799).seconds, 1)
        XCTAssertEqual(DispatchTimeInterval.seconds(10).seconds, 10)
        XCTAssertEqual(DispatchTimeInterval.seconds(1_912_912_412_241_952_111).seconds, 1_912_912_412_241_952_111)
        XCTAssertNil(DispatchTimeInterval.never.seconds)
    }

    func testMilliseconds() {
        XCTAssertEqual(DispatchTimeInterval.nanoseconds(6).milliseconds, 0)
        XCTAssertEqual(DispatchTimeInterval.nanoseconds(1000).milliseconds, 0)
        XCTAssertEqual(DispatchTimeInterval.microseconds(28).milliseconds, 0)
        XCTAssertEqual(DispatchTimeInterval.milliseconds(10).milliseconds, 10)
        XCTAssertEqual(DispatchTimeInterval.milliseconds(17).milliseconds, 17)
        XCTAssertEqual(DispatchTimeInterval.seconds(10).milliseconds, 10_000)
        XCTAssertNil(DispatchTimeInterval.never.milliseconds)
    }

    func testMicroseconds() {
        XCTAssertEqual(DispatchTimeInterval.nanoseconds(6).microseconds, 0)
        XCTAssertEqual(DispatchTimeInterval.nanoseconds(1000).microseconds, 1)
        XCTAssertEqual(DispatchTimeInterval.microseconds(28).microseconds, 28)
        XCTAssertEqual(DispatchTimeInterval.milliseconds(10).microseconds, 10_000)
        XCTAssertEqual(DispatchTimeInterval.milliseconds(17).microseconds, 17_000)
        XCTAssertEqual(DispatchTimeInterval.seconds(10).microseconds, 10_000_000)
        XCTAssertNil(DispatchTimeInterval.never.microseconds)
    }

    func testNanoseconds() {
        XCTAssertEqual(DispatchTimeInterval.nanoseconds(6).nanoseconds, 6)
        XCTAssertEqual(DispatchTimeInterval.nanoseconds(1000).nanoseconds, 1_000)
        XCTAssertEqual(DispatchTimeInterval.microseconds(28).nanoseconds, 28_000)
        XCTAssertEqual(DispatchTimeInterval.milliseconds(10).nanoseconds, 10_000_000)
        XCTAssertEqual(DispatchTimeInterval.milliseconds(17).nanoseconds, 17_000_000)
        XCTAssertEqual(DispatchTimeInterval.seconds(10).nanoseconds, 10_000_000_000)
        XCTAssertNil(DispatchTimeInterval.never.nanoseconds)
    }

    func testOverflow() {
        XCTAssertNil(DispatchTimeInterval.seconds(Int.max).nanoseconds)
        XCTAssertNil(DispatchTimeInterval.seconds(Int.max - 3).milliseconds)
        XCTAssertNil(DispatchTimeInterval.seconds(Int.max / 2).microseconds)

        XCTAssertEqual(DispatchTimeInterval.seconds(Int.max).timeInterval, Double(Int.max))
        XCTAssertEqual(DispatchTimeInterval.seconds(Int.max).seconds, Int.max)
        XCTAssertEqual(DispatchTimeInterval.milliseconds(Int.max).milliseconds, Int.max)
        XCTAssertEqual(DispatchTimeInterval.microseconds(Int.max).microseconds, Int.max)
        XCTAssertEqual(DispatchTimeInterval.nanoseconds(Int.max).nanoseconds, Int.max)
    }

    func testSumSamePrecision() {
        XCTAssertEqual(DispatchTimeInterval.seconds(1) + DispatchTimeInterval.seconds(20), DispatchTimeInterval.seconds(21))
        XCTAssertEqual(DispatchTimeInterval.milliseconds(1) + DispatchTimeInterval.milliseconds(20), DispatchTimeInterval.milliseconds(21))
        XCTAssertEqual(DispatchTimeInterval.microseconds(1) + DispatchTimeInterval.microseconds(20), DispatchTimeInterval.microseconds(21))
        XCTAssertEqual(DispatchTimeInterval.nanoseconds(1) + DispatchTimeInterval.nanoseconds(20), DispatchTimeInterval.nanoseconds(21))
    }

    func testSumDifferentPrecision() {
        XCTAssertEqual(DispatchTimeInterval.seconds(1) + DispatchTimeInterval.milliseconds(20), DispatchTimeInterval.milliseconds(1020))
        XCTAssertEqual(DispatchTimeInterval.microseconds(1000) + DispatchTimeInterval.milliseconds(1), DispatchTimeInterval.milliseconds(2))
        XCTAssertEqual(
            DispatchTimeInterval.nanoseconds(123) + DispatchTimeInterval.milliseconds(2), DispatchTimeInterval.nanoseconds(2_000_123))

        XCTAssertEqual(
            DispatchTimeInterval.seconds(1000) + DispatchTimeInterval.nanoseconds(1), DispatchTimeInterval.nanoseconds(1_000_000_000_001))
        XCTAssertEqual(
            DispatchTimeInterval.seconds(1000_000_000) + DispatchTimeInterval.nanoseconds(1),
            DispatchTimeInterval.nanoseconds(1_000_000_000_000_000_001))
        // nanoseconds will overflow here, so the result will be without nanoseconds
        XCTAssertEqual(
            DispatchTimeInterval.seconds(1000_000_000_000) + DispatchTimeInterval.nanoseconds(1),
            DispatchTimeInterval.seconds(1000_000_000_000))

        XCTAssertEqual(
            DispatchTimeInterval.seconds(1000) + DispatchTimeInterval.microseconds(1), DispatchTimeInterval.microseconds(1_000_000_001))
        XCTAssertEqual(
            DispatchTimeInterval.seconds(1000_000_000) + DispatchTimeInterval.microseconds(1),
            DispatchTimeInterval.microseconds(1_000_000_000_000_001))
        XCTAssertEqual(
            DispatchTimeInterval.seconds(1000_000_000_000) + DispatchTimeInterval.microseconds(1),
            DispatchTimeInterval.microseconds(1_000_000_000_000_000_001))
        // microseconds will overflow here, so the result will be without microseconds
        XCTAssertEqual(
            DispatchTimeInterval.seconds(1000_000_000_000_000) + DispatchTimeInterval.microseconds(1),
            DispatchTimeInterval.seconds(1000_000_000_000_000))

        XCTAssertEqual(
            DispatchTimeInterval.seconds(1000) + DispatchTimeInterval.milliseconds(1), DispatchTimeInterval.milliseconds(1_000_001))
        XCTAssertEqual(
            DispatchTimeInterval.seconds(1000_000_000) + DispatchTimeInterval.milliseconds(1),
            DispatchTimeInterval.milliseconds(1_000_000_000_001))
        XCTAssertEqual(
            DispatchTimeInterval.seconds(1000_000_000_000) + DispatchTimeInterval.milliseconds(1),
            DispatchTimeInterval.milliseconds(1_000_000_000_000_001))
        XCTAssertEqual(
            DispatchTimeInterval.seconds(1000_000_000_000_000) + DispatchTimeInterval.milliseconds(1),
            DispatchTimeInterval.milliseconds(1_000_000_000_000_000_001))
        // milliseconds will overflow here, so the result will be without milliseconds
        XCTAssertEqual(
            DispatchTimeInterval.seconds(1000_000_000_000_000_000) + DispatchTimeInterval.milliseconds(1),
            DispatchTimeInterval.seconds(1000_000_000_000_000_000))
    }

    func testSumWithNegative() {
        XCTAssertEqual(DispatchTimeInterval.seconds(-5) + DispatchTimeInterval.seconds(5), .zero)
        XCTAssertEqual(DispatchTimeInterval.seconds(-1000) + DispatchTimeInterval.milliseconds(1_000_000), .zero)
        XCTAssertEqual(DispatchTimeInterval.milliseconds(-21) + DispatchTimeInterval.nanoseconds(21_000_000), .zero)
        XCTAssertEqual(DispatchTimeInterval.nanoseconds(-1_420_974) + DispatchTimeInterval.microseconds(1_420), .nanoseconds(-974))
    }

    func testComparison() {
        XCTAssert(DispatchTimeInterval.seconds(10) > DispatchTimeInterval.seconds(5))
        XCTAssert(DispatchTimeInterval.milliseconds(10) > DispatchTimeInterval.milliseconds(5))
        XCTAssert(DispatchTimeInterval.microseconds(10) > DispatchTimeInterval.microseconds(5))
        XCTAssert(DispatchTimeInterval.nanoseconds(10) > DispatchTimeInterval.nanoseconds(5))

        XCTAssert(DispatchTimeInterval.seconds(-10) < DispatchTimeInterval.seconds(5))
        XCTAssert(DispatchTimeInterval.seconds(-1000) < DispatchTimeInterval.nanoseconds(-500))
        XCTAssert(DispatchTimeInterval.nanoseconds(2) > DispatchTimeInterval.microseconds(-1))

        XCTAssert(DispatchTimeInterval.seconds(1) > DispatchTimeInterval.milliseconds(500))
        XCTAssert(DispatchTimeInterval.milliseconds(1) > DispatchTimeInterval.microseconds(500))
        XCTAssert(DispatchTimeInterval.microseconds(1) > DispatchTimeInterval.nanoseconds(500))

        XCTAssert(DispatchTimeInterval.seconds(1) < DispatchTimeInterval.milliseconds(1100))
        XCTAssert(DispatchTimeInterval.milliseconds(1) < DispatchTimeInterval.microseconds(1100))
        XCTAssert(DispatchTimeInterval.microseconds(1) < DispatchTimeInterval.nanoseconds(1100))


        XCTAssert(DispatchTimeInterval.seconds(1000_000_000_000_000_000) > DispatchTimeInterval.nanoseconds(10))
        XCTAssert(DispatchTimeInterval.nanoseconds(9) < DispatchTimeInterval.seconds(1000_000_000_000_000_000))

        XCTAssert(DispatchTimeInterval.nanoseconds(1000_000_000_000_000_000) > DispatchTimeInterval.milliseconds(10))
        XCTAssert(DispatchTimeInterval.microseconds(9) < DispatchTimeInterval.nanoseconds(1000_000_000_000_000_000))

        XCTAssert(DispatchTimeInterval.seconds(1000_000_000_000_000_000) > DispatchTimeInterval.nanoseconds(1000_000_000_000_000_000))
        XCTAssert(DispatchTimeInterval.nanoseconds(1000_000_000_000_000_000) < DispatchTimeInterval.seconds(1000_000_000_000_000_000))
    }
}
