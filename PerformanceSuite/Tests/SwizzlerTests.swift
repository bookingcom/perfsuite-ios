//
//  SwizzlerTests.swift
//  PerformanceSuite
//
//  Created by Gleb Tarasov on 05/07/2021.
//

import XCTest

@testable import PerformanceSuite

// swiftlint:disable type_name
class SwizzlerTests: XCTestCase {

    func testSecondSwizzleFails() throws {
        let selector = #selector(C1.testMethod1Param(p1:))
        try Swizzler.swizzle(class: C1.self, selector: selector) { _ in }

        XCTAssertThrowsError(try Swizzler.swizzle(class: C1.self, selector: selector) { _ in }, "") { error in
            XCTAssertEqual(
                error.localizedDescription,
                "You are trying to swizzle method testMethod1ParamWithP1: in class C1 that was already swizzled. You should unswizzle before that."
            )
        }

        try Swizzler.unswizzle(class: C1.self, selector: selector)
    }

    func testSecondUnswizzleFails() throws {
        let selector = #selector(C1.testMethod1Param(p1:))
        try Swizzler.swizzle(class: C1.self, selector: selector) { _ in }
        try Swizzler.unswizzle(class: C1.self, selector: selector)
        XCTAssertThrowsError(try Swizzler.unswizzle(class: C1.self, selector: selector), "") { error in
            XCTAssertEqual(
                error.localizedDescription, "You are trying to unswizzle method testMethod1ParamWithP1: in class C1 that wasn't swizzled.")
        }
    }

    func testNonExistingSwizzleFails() throws {
        let selector = NSSelectorFromString("testMethod0Params")
        XCTAssertThrowsError(try Swizzler.swizzle(class: C1.self, selector: selector) { _ in }, "") { error in
            XCTAssertEqual(error.localizedDescription, "No method testMethod0Params found in class C1.")
        }
    }

    func testNonExistingUnswizzleFails() throws {
        let selector = NSSelectorFromString("testMethod0Params")
        XCTAssertThrowsError(try Swizzler.unswizzle(class: C1.self, selector: selector), "") { error in
            XCTAssertEqual(
                error.localizedDescription, "You are trying to unswizzle method testMethod0Params in class C1 that wasn't swizzled.")
        }
    }

    func testSwizzleWorks() throws {
        let selector = #selector(C1.testMethod2Params(p1:p2:))


        try Swizzler.swizzle(class: C1.self, selector: selector) { [unowned self] (c1: C1) in self.lastCalled = c1 }

        let c1 = C1()
        XCTAssertNil(lastCalled)
        c1.testMethod2Params(p1: 1, p2: NSObject())
        XCTAssertNotNil(c1.lastP1)
        XCTAssertEqual(lastCalled, c1)

        try Swizzler.unswizzle(class: C1.self, selector: selector)
    }

    func testUnswizzleWorks() throws {
        let selector = #selector(C1.testMethod2Params(p1:p2:))

        lastCalled = nil
        try Swizzler.swizzle(class: C1.self, selector: selector) { [unowned self] (c1: C1) in self.lastCalled = c1 }
        try Swizzler.unswizzle(class: C1.self, selector: selector)

        let c1 = C1()
        XCTAssertNil(lastCalled)
        c1.testMethod2Params(p1: 1, p2: NSObject())
        XCTAssertNotNil(c1.lastP1)
        XCTAssertNil(lastCalled)
    }

    func testSwizzleUnswizzleSeveralTimes() throws {
        let selector = #selector(C1.testMethod1Param(p1:))
        try Swizzler.swizzle(class: C1.self, selector: selector) { [unowned self] (c1: C1) in self.lastCalled = c1 }
        try Swizzler.unswizzle(class: C1.self, selector: selector)

        try Swizzler.swizzle(class: C1.self, selector: selector) { [unowned self] (c1: C1) in self.lastCalled = c1 }
        try Swizzler.unswizzle(class: C1.self, selector: selector)

        try Swizzler.swizzle(class: C1.self, selector: selector) { [unowned self] (c1: C1) in self.lastCalled = c1 }
        try Swizzler.unswizzle(class: C1.self, selector: selector)

        try Swizzler.swizzle(class: C1.self, selector: selector) { [unowned self] (c1: C1) in self.lastCalled = c1 }
        try Swizzler.unswizzle(class: C1.self, selector: selector)

        try Swizzler.swizzle(class: C1.self, selector: selector) { [unowned self] (c1: C1) in self.lastCalled = c1 }
        try Swizzler.unswizzle(class: C1.self, selector: selector)
    }

    func testSwizzleWorksForSubclass() throws {
        let selector = #selector(C1.testMethod2Params(p1:p2:))

        lastCalled = nil
        try Swizzler.swizzle(class: C1.self, selector: selector) { [unowned self] (c1: C1) in self.lastCalled = c1 }
        let c2 = C2()
        XCTAssertNil(lastCalled)
        c2.testMethod2Params(p1: 1, p2: NSObject())
        XCTAssertNotNil(c2.lastP1)
        XCTAssertEqual(lastCalled, c2)

        try Swizzler.unswizzle(class: C1.self, selector: selector)
    }

    func testSwizzleBeforeWorks() throws {
        let selector = #selector(C1.testMethod1Param(p1:))
        var swizzledCalled = false
        try Swizzler.swizzle(class: C1.self, selector: selector, after: false) { (c1: C1) in
            XCTAssert(c1.lastP1 as? Bool == nil)
            swizzledCalled = true
        }

        let c1 = C1()
        XCTAssertNil(c1.lastP1)
        XCTAssertFalse(swizzledCalled)
        _ = c1.testMethod1Param(p1: true)
        XCTAssertTrue(swizzledCalled)

        try Swizzler.unswizzle(class: C1.self, selector: selector)
    }

    func testSwizzleAfterWorks() throws {
        let selector = #selector(C1.testMethod1Param(p1:))
        var swizzledCalled = false
        try Swizzler.swizzle(class: C1.self, selector: selector, after: true) { (c1: C1) in
            XCTAssert(c1.lastP1 as? Bool == true)
            swizzledCalled = true
        }

        let c1 = C1()
        XCTAssertNil(c1.lastP1)
        XCTAssertFalse(swizzledCalled)
        _ = c1.testMethod1Param(p1: true)
        XCTAssertTrue(swizzledCalled)

        try Swizzler.unswizzle(class: C1.self, selector: selector)
    }

    private var lastCalled: C1?
}


@objc private class C1: NSObject {

    var lastP1: Any?
    var lastP2: Any?
    var lastP3: Any?

    func clearParams() {
        lastP1 = nil
        lastP2 = nil
        lastP3 = nil
    }

    @objc dynamic func testMethodNoParams() {
    }

    @objc dynamic func testMethod1Param(p1: Bool) -> String {
        lastP1 = p1
        return "\(p1)"
    }

    @objc dynamic func testMethod2Params(p1: NSNumber, p2: NSObject) {
        lastP1 = p1
        lastP2 = p2
    }

    @objc dynamic func testMethod3Params(p1: Int, p2: String, p3: NSObject) -> String {
        lastP1 = p1
        lastP2 = p2
        lastP3 = p3
        return p2 + "test"
    }
}

@objc private class C2: C1 {
    var lastP1C2: Any?
    var lastP2C2: Any?

    override func clearParams() {
        super.clearParams()
        lastP1C2 = nil
        lastP2C2 = nil
    }

    override func testMethod2Params(p1: NSNumber, p2: NSObject) {
        super.testMethod2Params(p1: p1, p2: p2)
        lastP1C2 = p1
        lastP2C2 = p2
    }
}
