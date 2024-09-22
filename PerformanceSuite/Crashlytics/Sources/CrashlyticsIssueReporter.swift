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
#if canImport(PerformanceSuite)
import PerformanceSuite
#endif

// this type is used for crashes to log all threads stack traces
private let firebaseNativeErrorType: Int32 = 1

class CrashlyticsIssueReporter {

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
            // for all the threads
            result = FIRCLSExceptionRecordOnDemand(firebaseNativeErrorType, name, reason, model.stackTrace, true, 0, 0)
        } else {
            // We are not using `record(onDemandExceptionModel: model)` here,
            // because then the report will be sent right away,
            // but we do not know if it should by fatal or non-fatal hang yet.
            result = FIRCLSExceptionRecordOnDemandModel(model, 0, 0)
        }

        if fatalHangsAsCrashes {
            // this shouldn't happen, but remove the previous marker
            // if it is still there
            removeFirebaseCrashMarker()
        }
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
            Crashlytics.crashlytics().record(onDemandExceptionModel: model)

            if fatalHangsAsCrashes {
                removeFirebaseCrashMarker()
            }
        } catch {
            debugPrint("Failed to change hang report type with error: \(error)")
        }
    }

    private func removeFirebaseCrashMarker() {
        guard let crashedMarkerFileName = String(utf8String: FIRCLSCrashedMarkerFileName),
              let rootPath = Crashlytics.crashlytics().fileManager?.rootPath else {
            debugPrint("Failed to get path for Crashlytics crash marker file")
            return
        }

        let crashedMarkerFileFullPath = (rootPath as NSString).appendingPathComponent(crashedMarkerFileName)
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
