//
//  CrashlyticsIssueReporter.swift
//  PerformanceSuite
//
//  Created by Gleb Tarasov on 07/09/2024.
//

import FirebaseCrashlytics

// In SwiftPM we have separate targets
#if canImport(CrashlyticsImports)
import CrashlyticsImports
#endif
#if canImport(PerformanceSuiteCrashlytics)
import PerformanceSuite
#endif

// this type is used for crashes to log all threads stack traces
private let firebaseNativeErrorType: Int32 = 1

protocol CrashlyticsIssueReporting {
    func reportHangStarted(withType hangType: String, stackTrace: String) -> String
    func changeExistingHangReport(toType type: String, stackTrace: String, reportPath: String)

    var fatalHangsAsCrashes: Bool { get }
    var firebaseHangReason: String { get }
}

class CrashlyticsIssueReporter: CrashlyticsIssueReporting {

    init(fatalHangsAsCrashes: Bool, firebaseHangReason: String) {
        self.fatalHangsAsCrashes = fatalHangsAsCrashes
        self.firebaseHangReason = firebaseHangReason
    }

    let fatalHangsAsCrashes: Bool
    let firebaseHangReason: String

    func reportHangStarted(withType type: String, stackTrace: String) -> String {
        let model = exceptionModel(withName: type, stackTrace: stackTrace)
        let result: String
        if fatalHangsAsCrashes {
            guard let name = (type as NSString).utf8String,
                  let reason = (firebaseHangReason as NSString).utf8String else {
                debugPrint("Wrong name or reason passed")
                return ""
            }

            // We are passing crash error type here, so that stack trace is recorded
            // for all the threads.
            // Last argument is `shouldSuspendThread` (added in Firebase 11.9.0); we pass `true`
            // to match Firebase's own default and preserve the all-thread snapshot behavior.
            result = FIRCLSExceptionRecordOnDemand(firebaseNativeErrorType, name, reason, model.stackTrace, true, 0, 0, true)
        } else {
            // We are not using `record(onDemandExceptionModel: model)` here,
            // because then the report will be sent right away,
            // but we do not know if it should by fatal or non-fatal hang yet.
            // Last argument is `shouldSuspendThread` (added in Firebase 11.9.0); we pass `true`
            // to match Firebase's own default.
            result = FIRCLSExceptionRecordOnDemandModel(model, 0, 0, true)
        }

        // Ensure, that crash marker is not created
        // (so that `didCrashPreviously` returns false on the next launch)
        removeFirebaseCrashMarker()

        return result
    }

    func changeExistingHangReport(toType type: String, stackTrace: String, reportPath: String) {
        do {
            // If hang turned out to be non-fatal, we remove fatal report,
            // and create a non-fatal one. Send it right away.
            guard !reportPath.isEmpty else {
                debugPrint("Existing hang report path was empty")
                return
            }
            try FileManager.default.removeItem(atPath: reportPath)

            let model = exceptionModel(withName: type, stackTrace: stackTrace)
            let crashlytics = Crashlytics.crashlytics()
            crashlytics.record(onDemandExceptionModel: model)

            // `record(onDemandExceptionModel:)` records an on-demand exception, which always
            // writes Firebase's "previously-crashed" marker (even for a non-fatal model). A
            // recovered hang is never a crash, so we must always clear the marker here -
            // regardless of the reporting mode - otherwise the next launch reports a phantom
            // crash via `didCrashDuringPreviousExecution()`. This mirrors `reportHangStarted`,
            // which also removes the marker unconditionally.
            //
            // Since Firebase 12.11.0, `record(onDemandExceptionModel:)` defers its work (the
            // marker write included) onto an internal context-init promise instead of running
            // synchronously. A synchronous `removeFirebaseCrashMarker()` here would race ahead
            // of that deferred write, leaving the marker in place. We chain our removal on the
            // same promise via `waitForContextInit` *after* the record call: FBLPromise invokes
            // observers in registration order on the main queue, and the record's marker write
            // is synchronous within its own observer, so our removal is guaranteed to run after
            // the marker has been (re)written. (`reportHangStarted` is unaffected: it records
            // through the synchronous `FIRCLSExceptionRecordOnDemand*` C functions, which Firebase
            // never wrapped.)
            // Capture `self` strongly: the removal must run even if the caller releases this
            // reporter before the promise resolves (otherwise the deferred marker *write* would
            // survive with no removal). The closure is owned by Firebase's one-shot promise
            // observer, not by `self`, so there is no retain cycle.
            crashlytics.wait(forContextInit: "perfSuiteHangMarkerRemoval") {
                self.removeFirebaseCrashMarker()
            }
        } catch {
            debugPrint("Failed to change hang report type with error: \(error)")
        }
    }

    var crashedMarkerFileFullPath: String? {
        guard let crashedMarkerFileName = String(utf8String: FIRCLSCrashedMarkerFileName),
              let rootPath = Crashlytics.crashlytics().fileManager?.rootPath else {
            return nil
        }

        return (rootPath as NSString).appendingPathComponent(crashedMarkerFileName)
    }

    func removeFirebaseCrashMarker() {
        guard let crashedMarkerFileFullPath else {
            debugPrint("Failed to get path for Crashlytics crash marker file")
            return
        }
        try? FileManager.default.removeItem(atPath: crashedMarkerFileFullPath)
    }

    private func exceptionModel(withName name: String, stackTrace: String) -> ExceptionModel {
        let stackFrames = parse(stackTrace: stackTrace)
        let model = ExceptionModel(name: name, reason: firebaseHangReason)
        model.stackTrace = stackFrames
        return model
    }

    /// Helper function to convert text stack trace into the array of addresses to be ready to send them to Firebase
    func parse(stackTrace: String) -> [StackFrame] {
        let lines = stackTrace.split(separator: "\n")
        return lines.compactMap { line in
            let components = line.split(whereSeparator: { $0.isWhitespace })
            if components.count == 6,
               let address = UInt(components[2].dropFirst(2), radix: 16) {
                return StackFrame(address: address)
            } else {
                return nil
            }
        }
    }
}
