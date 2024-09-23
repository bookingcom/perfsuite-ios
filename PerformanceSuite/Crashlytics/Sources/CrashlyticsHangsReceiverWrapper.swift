//
//  CrashlyticsHangsReceiverWrapper.swift
//  PerformanceSuite
//
//  Created by Gleb Tarasov on 07/09/2024.
//

// In SwiftPM we have separate targets
#if canImport(PerformanceSuiteCrashlytics)
import PerformanceSuite
#endif

/// Settings how to report hangs to Crashlytics
/// - how to format issue name depending on the type of a hang
/// - which types to use (fatal/non-fatal)
/// - default "reason" for the issue
public struct CrashlyticsHangsSettings {
    public let reportingMode: CrashlyticsHangsReportingMode
    public let hangReason: String
    public let hangTypeFormatter: HangTypeFormatter


    /// Settings how to report hangs to Crashlytics
    /// - Parameters:
    ///   - reportingMode: How should we report fatal hangs: fatals or non-fatals
    ///   - hangReason: Default string reason for all hang issues
    ///   - hangTypeFormatter: How to name hang issues depending on the type of a hang
    public init(reportingMode: CrashlyticsHangsReportingMode = .fatalHangsAsCrashes,
                hangReason: String = "hang",
                hangTypeFormatter: @escaping HangTypeFormatter = defaultHangTypeFormatter) {
        self.reportingMode = reportingMode
        self.hangReason = hangReason
        self.hangTypeFormatter = hangTypeFormatter
    }
}

public func defaultHangTypeFormatter(_ fatal: Bool, startup: Bool) -> String {
    startup
        ? (fatal ? "ios_startup_fatal_hang" : "ios_startup_non_fatal_hang")
        : (fatal ? "ios_fatal_hang" : "ios_non_fatal_hang")
}

/// Customization mode how to send hangs to Firebase Crashlytics
public enum CrashlyticsHangsReportingMode {
    case fatalHangsAsCrashes
    case fatalHangsAsNonFatals

    var sendFatalHangsAsCrashes: Bool {
        return self == .fatalHangsAsCrashes
    }
}

/// Formatter generates name for the Crashlytics issue depending on fatal/non-fatal, startup/non-startup
public typealias HangTypeFormatter = (_ fatal: Bool, _ startup: Bool) -> String

/// This is a wrapper around the custom `HangsReceiver` that
/// will send hangs to Firebase Crashlytics.
public class CrashlyticsHangsReceiverWrapper: HangsReceiver {

    public convenience init(hangsReceiver: HangsReceiver,
                            settings: CrashlyticsHangsSettings) {
        let issueReporter = CrashlyticsIssueReporter(
            fatalHangsAsCrashes: settings.reportingMode.sendFatalHangsAsCrashes,
            firebaseHangReason: settings.hangReason)
        self.init(hangsReceiver: hangsReceiver, settings: settings, issueReporter: issueReporter)
    }

    init(hangsReceiver: HangsReceiver,
         settings: CrashlyticsHangsSettings,
         issueReporter: CrashlyticsIssueReporting) {
        self.issueReporter = issueReporter
        self.hangsReceiver = hangsReceiver
        self.reportingMode = settings.reportingMode
        self.hangTypeFormatter = settings.hangTypeFormatter
    }

    let hangsReceiver: HangsReceiver
    let reportingMode: CrashlyticsHangsReportingMode
    let hangTypeFormatter: HangTypeFormatter
    let issueReporter: CrashlyticsIssueReporting

    private var lastHangReport: String?

    // MARK: - HangsReceiver

    public func fatalHangReceived(info: HangInfo) {
        hangsReceiver.fatalHangReceived(info: info)

        // on the next launch we shouldn't do anything
    }

    public func nonFatalHangReceived(info: HangInfo) {
        hangsReceiver.nonFatalHangReceived(info: info)

        // if hang turned out to be a non-fatal hang,
        // we change existing report type to "non-fatal"
        if let reportPath = lastHangReport {
            let hangType = hangTypeFormatter(false, info.duringStartup)
            issueReporter.changeExistingHangReport(toType: hangType,
                                                   stackTrace: info.callStack,
                                                   reportPath: reportPath)
        }
    }

    public func hangStarted(info: HangInfo) {
        hangsReceiver.hangStarted(info: info)

        // when hang starts, we create report as "fatal hang"
        // so that if app is terminated, this report stays as fatal
        let hangType = hangTypeFormatter(true, info.duringStartup)
        lastHangReport = issueReporter.reportHangStarted(withType: hangType,
                                                         stackTrace: info.callStack)
    }
}
