//
//  CrashlyticsHangsReceiverWrapperTests.swift
//  Pods
//
//  Created by Gleb Tarasov on 23/09/2024.
//

import XCTest
@testable import PerformanceSuite

class CrashlyticsHangsReceiverWrapperTests: XCTestCase {

    func testHangStarted_callsHangsReceiverAndReportsHangStarted() {
        let mockHangsReceiver = MockHangsReceiver()
        let settings = CrashlyticsHangsSettings()
        let mockIssueReporter = MockCrashlyticsIssueReporter()
        let wrapper = CrashlyticsHangsReceiverWrapper(
            hangsReceiver: mockHangsReceiver,
            settings: settings,
            issueReporter: mockIssueReporter
        )

        let hangInfo = HangInfo.with(callStack: "stack", duringStartup: false, duration: .seconds(1))
        wrapper.hangStarted(info: hangInfo)

        XCTAssertTrue(mockHangsReceiver.hangStartedCalled)
        XCTAssertEqual(mockHangsReceiver.hangStartedInfo?.duringStartup, hangInfo.duringStartup)
        XCTAssertEqual(mockHangsReceiver.hangStartedInfo?.callStack, hangInfo.callStack)

        XCTAssertTrue(mockIssueReporter.reportHangStartedCalled)
        let expectedHangType = settings.hangTypeFormatter(true, hangInfo.duringStartup)
        XCTAssertEqual(mockIssueReporter.reportHangStartedHangType, expectedHangType)
        XCTAssertEqual(mockIssueReporter.reportHangStartedStackTrace, hangInfo.callStack)
    }

    func testNonFatalHangReceived_callsHangsReceiverAndChangesExistingHangReport() {
        let mockHangsReceiver = MockHangsReceiver()
        let settings = CrashlyticsHangsSettings()
        let mockIssueReporter = MockCrashlyticsIssueReporter()
        let wrapper = CrashlyticsHangsReceiverWrapper(
            hangsReceiver: mockHangsReceiver,
            settings: settings,
            issueReporter: mockIssueReporter
        )

        // Simulate that hangStarted was called earlier
        mockIssueReporter.reportHangStartedReturnValue = "/path/to/report"
        let hangStartedInfo = HangInfo.with(callStack: "stack", duringStartup: true, duration: .microseconds(120))
        wrapper.hangStarted(info: hangStartedInfo)

        let hangInfo = HangInfo.with(callStack: "stack2", duringStartup: false, duration: .microseconds(200))
        wrapper.nonFatalHangReceived(info: hangInfo)

        XCTAssertTrue(mockHangsReceiver.nonFatalHangReceivedCalled)
        XCTAssertEqual(mockHangsReceiver.nonFatalHangReceivedInfo?.duringStartup, false)
        XCTAssertEqual(mockHangsReceiver.nonFatalHangReceivedInfo?.callStack, "stack2")

        XCTAssertTrue(mockIssueReporter.changeExistingHangReportCalled)
        XCTAssertEqual(mockIssueReporter.changeExistingHangReportHangType, "ios_non_fatal_hang")
        XCTAssertEqual(mockIssueReporter.changeExistingHangReportStackTrace, hangInfo.callStack)
        XCTAssertEqual(mockIssueReporter.changeExistingHangReportReportPath, "/path/to/report")
    }

    func testNonFatalHangReceived_doesNotChangeExistingHangReportIfNoLastHangReport() {
        let mockHangsReceiver = MockHangsReceiver()
        let settings = CrashlyticsHangsSettings()
        let mockIssueReporter = MockCrashlyticsIssueReporter()
        let wrapper = CrashlyticsHangsReceiverWrapper(
            hangsReceiver: mockHangsReceiver,
            settings: settings,
            issueReporter: mockIssueReporter
        )

        let hangInfo = HangInfo.with(callStack: "stack", duringStartup: true, duration: .microseconds(200))
        wrapper.nonFatalHangReceived(info: hangInfo)

        XCTAssertTrue(mockHangsReceiver.nonFatalHangReceivedCalled)
        XCTAssertEqual(mockHangsReceiver.nonFatalHangReceivedInfo?.duringStartup, true)
        XCTAssertEqual(mockHangsReceiver.nonFatalHangReceivedInfo?.callStack, "stack")

        XCTAssertFalse(mockIssueReporter.changeExistingHangReportCalled)
    }

    func testFatalHangReceived_callsHangsReceiverAndDoesNotInteractWithIssueReporter() {
        let mockHangsReceiver = MockHangsReceiver()
        let settings = CrashlyticsHangsSettings()
        let mockIssueReporter = MockCrashlyticsIssueReporter()
        let wrapper = CrashlyticsHangsReceiverWrapper(
            hangsReceiver: mockHangsReceiver,
            settings: settings,
            issueReporter: mockIssueReporter
        )

        let hangInfo = HangInfo.with(callStack: "stack", duringStartup: false, duration: .microseconds(200))
        wrapper.fatalHangReceived(info: hangInfo)

        XCTAssertTrue(mockHangsReceiver.fatalHangReceivedCalled)
        XCTAssertEqual(mockHangsReceiver.fatalHangReceivedInfo?.duringStartup, hangInfo.duringStartup)
        XCTAssertEqual(mockHangsReceiver.fatalHangReceivedInfo?.callStack, hangInfo.callStack)

        XCTAssertFalse(mockIssueReporter.reportHangStartedCalled)
        XCTAssertFalse(mockIssueReporter.changeExistingHangReportCalled)
    }

    func testHangTypeFormatterIsUsedCorrectly() {
        let mockHangsReceiver = MockHangsReceiver()
        let customHangTypeFormatter: HangTypeFormatter = { fatal, startup in
            return "custom_\(fatal ? "fatal" : "nonfatal")_\(startup ? "startup" : "regular")"
        }
        let settings = CrashlyticsHangsSettings(hangTypeFormatter: customHangTypeFormatter)
        let mockIssueReporter = MockCrashlyticsIssueReporter()
        let wrapper = CrashlyticsHangsReceiverWrapper(
            hangsReceiver: mockHangsReceiver,
            settings: settings,
            issueReporter: mockIssueReporter
        )

        mockIssueReporter.reportHangStartedReturnValue = "/path/to/report"
        let hangStartedInfo = HangInfo.with(callStack: "stack", duringStartup: true, duration: .microseconds(100))
        wrapper.hangStarted(info: hangStartedInfo)

        XCTAssertTrue(mockIssueReporter.reportHangStartedCalled)
        let expectedHangTypeStarted = "custom_fatal_startup"
        XCTAssertEqual(mockIssueReporter.reportHangStartedHangType, expectedHangTypeStarted)

        let hangInfo = HangInfo.with(callStack: "stack2", duringStartup: true, duration: .microseconds(100))
        wrapper.nonFatalHangReceived(info: hangInfo)

        XCTAssertTrue(mockIssueReporter.changeExistingHangReportCalled)
        let expectedHangTypeReceived = "custom_nonfatal_startup"
        XCTAssertEqual(mockIssueReporter.changeExistingHangReportHangType, expectedHangTypeReceived)
    }
}


private class MockHangsReceiver: HangsReceiver {
    var fatalHangReceivedCalled = false
    var nonFatalHangReceivedCalled = false
    var hangStartedCalled = false

    var fatalHangReceivedInfo: HangInfo?
    var nonFatalHangReceivedInfo: HangInfo?
    var hangStartedInfo: HangInfo?

    func fatalHangReceived(info: HangInfo) {
        fatalHangReceivedCalled = true
        fatalHangReceivedInfo = info
    }

    func nonFatalHangReceived(info: HangInfo) {
        nonFatalHangReceivedCalled = true
        nonFatalHangReceivedInfo = info
    }

    func hangStarted(info: HangInfo) {
        hangStartedCalled = true
        hangStartedInfo = info
    }
}

private class MockCrashlyticsIssueReporter: CrashlyticsIssueReporting {

    var fatalHangsAsCrashes: Bool = false
    var firebaseHangReason: String = "reason"


    var reportHangStartedCalled = false
    var reportHangStartedHangType: String?
    var reportHangStartedStackTrace: String?
    var reportHangStartedReturnValue: String = ""

    var changeExistingHangReportCalled = false
    var changeExistingHangReportHangType: String?
    var changeExistingHangReportStackTrace: String?
    var changeExistingHangReportReportPath: String?

    func reportHangStarted(withType hangType: String, stackTrace: String) -> String {
        reportHangStartedCalled = true
        reportHangStartedHangType = hangType
        reportHangStartedStackTrace = stackTrace
        return reportHangStartedReturnValue
    }

    func changeExistingHangReport(toType hangType: String, stackTrace: String, reportPath: String) {
        changeExistingHangReportCalled = true
        changeExistingHangReportHangType = hangType
        changeExistingHangReportStackTrace = stackTrace
        changeExistingHangReportReportPath = reportPath
    }
}
