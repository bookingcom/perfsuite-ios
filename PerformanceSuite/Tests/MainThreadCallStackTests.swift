//
//  MainThreadCallStackTests.swift
//  PerformanceSuite-Tests
//
//  Created by Gleb Tarasov on 01/07/2022.
//

import XCTest

@testable import PerformanceSuite

#if arch(arm64)
    // swiftlint:disable force_try
    class MainThreadCallStackTests: XCTestCase {

        func testCallStack() throws {
            MainThreadCallStack.storeMainThread()
            let exp = expectation(description: "test")
            DispatchQueue.global().async {
                let stack = try! MainThreadCallStack.readStack()
                XCTAssert(stack.contains("XCTestCore"))
                exp.fulfill()
            }
            waitForExpectations(timeout: 1)
        }

        func testCallStackConversion() throws {
            setenv("ActivePrewarm", "1", 1)
            AppInfoHolder.resetForTests()
            AppInfoHolder.recordMainStarted()
            AppInfoHolder.screenOpened("screen1")
            AppInfoHolder.screenOpened("screen2")

            let hangInfo = HangInfo.with(callStack: "stack_trace bla bla bla", duringStartup: true, duration: .milliseconds(2001))
            XCTAssert(hangInfo.architecture.contains("arm"))
            XCTAssert(hangInfo.iOSVersion.contains("."))
            XCTAssertEqual(hangInfo.callStack, "stack_trace bla bla bla")
            XCTAssertTrue(hangInfo.appStartInfo.appStartedWithPrewarming)
            XCTAssertEqual(hangInfo.appRuntimeInfo.openedScreens, ["screen1", "screen2"])
            XCTAssertTrue(hangInfo.duringStartup)
            XCTAssertEqual(hangInfo.duration.milliseconds, 2001)

            let data = try! JSONEncoder().encode(hangInfo)
            let hangInfo2: HangInfo = try! JSONDecoder().decode(HangInfo.self, from: data)
            XCTAssert(hangInfo2.architecture.contains("arm"))
            XCTAssert(hangInfo2.iOSVersion.contains("."))
            XCTAssertEqual(hangInfo2.callStack, "stack_trace bla bla bla")
            XCTAssertTrue(hangInfo2.appStartInfo.appStartedWithPrewarming)
            XCTAssertEqual(hangInfo2.appRuntimeInfo.openedScreens, ["screen1", "screen2"])

            XCTAssertTrue(hangInfo2.duringStartup)
            XCTAssertEqual(hangInfo2.duration.milliseconds, 2001)
            enum Key: String {
                case key
            }
            UserDefaults.standard.writeJSON(key: Key.key, value: hangInfo2)
            let stack3Nullable: HangInfo? = UserDefaults.standard.readJSON(key: Key.key)
            let stack3 = try XCTUnwrap(stack3Nullable)
            XCTAssert(stack3.architecture.contains("arm"))
            XCTAssert(stack3.iOSVersion.contains("."))
            XCTAssertEqual(stack3.callStack, "stack_trace bla bla bla")
            XCTAssertTrue(stack3.appStartInfo.appStartedWithPrewarming)
            XCTAssertEqual(stack3.appRuntimeInfo.openedScreens, ["screen1", "screen2"])
            XCTAssertTrue(stack3.duringStartup)
            XCTAssertEqual(stack3.duration.milliseconds, 2001)

            setenv("ActivePrewarm", "", 1)
        }
    }
#endif
