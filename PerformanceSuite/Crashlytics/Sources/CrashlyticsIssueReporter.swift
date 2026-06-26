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

// Polling parameters used to clear the "previously-crashed" marker that a deferred on-demand
// `record(onDemandExceptionModel:)` re-writes (see `changeExistingHangReport`).
private let crashMarkerPollInterval: TimeInterval = 0.005
private let crashMarkerPollMaxAttempts = 100

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

    /// Serial queue used to poll for and clear the crash marker that a deferred on-demand
    /// `record(onDemandExceptionModel:)` re-writes (see `changeExistingHangReport`).
    private let markerRemovalQueue = DispatchQueue(label: "com.perfsuite.crashMarkerRemoval")

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

            // We use `record(onDemandExceptionModel:)` (not the synchronous C function
            // `FIRCLSExceptionRecordOnDemandModel`) so the recovered non-fatal hang is uploaded
            // right away instead of only on the next launch.
            //
            // Recording any on-demand exception writes Firebase's "previously-crashed" marker,
            // which we must then remove (a recovered hang is never a crash) - otherwise the next
            // launch mis-reports it as an app crash via `didCrashDuringPreviousExecution()`.
            //
            // Since Firebase 12.11.0, `record(onDemandExceptionModel:)` no longer runs
            // synchronously: it defers its work (the marker write included) onto Firebase's
            // internal context-init promise. We therefore clear the marker only once that promise
            // has resolved - the point at which the deferred write happens - and even then poll for
            // it, because the promise's observers have no guaranteed ordering: the write may land
            // in our `waitForContextInit` callback (then the poll removes it immediately) or just
            // after it (then the poll waits the brief moment for it to land). Anchoring the poll to
            // the promise - rather than starting it at this call site - is what makes its short
            // budget sufficient in every environment.
            let crashlytics = Crashlytics.crashlytics()
            crashlytics.record(onDemandExceptionModel: model)
            crashlytics.wait(forContextInit: "perfSuiteHangMarkerRemoval") {
                self.removeCrashMarkerAfterDeferredOnDemandWrite()
            }
        } catch {
            debugPrint("Failed to change hang report type with error: \(error)")
        }
    }

    /// `record(onDemandExceptionModel:)` writes Firebase's "previously-crashed" marker as deferred,
    /// unordered work, so we cannot remove it inline or via a single chained promise observer. Poll
    /// for the write to land (it is one-shot), then clear it - once removed *after* the write, it
    /// stays gone for the next launch. If the marker never appears (e.g. the on-demand event was
    /// dropped for quota), we simply time out with nothing to remove.
    ///
    /// We capture `self` strongly on purpose: the marker removal must run even if the caller
    /// releases this reporter before the deferred write lands - otherwise the marker would survive
    /// and the next launch would report a phantom crash. The capture is a temporary cycle
    /// (self -> queue -> pending block -> self) that breaks as soon as the bounded poll finishes.
    private func removeCrashMarkerAfterDeferredOnDemandWrite() {
        // Single hop onto our serial queue; the poll then reschedules itself in place.
        markerRemovalQueue.async {
            self.pollForAndRemoveCrashMarker(attemptsLeft: crashMarkerPollMaxAttempts)
        }
    }

    /// Must be called on `markerRemovalQueue`. Removes the marker if present, otherwise reschedules
    /// itself on the same queue (no extra cross-queue hop) until it appears or the budget runs out.
    private func pollForAndRemoveCrashMarker(attemptsLeft: Int) {
        if let path = crashedMarkerFileFullPath, FileManager.default.fileExists(atPath: path) {
            removeFirebaseCrashMarker()
            return
        }
        guard attemptsLeft > 0 else {
            return
        }
        markerRemovalQueue.asyncAfter(deadline: .now() + crashMarkerPollInterval) {
            self.pollForAndRemoveCrashMarker(attemptsLeft: attemptsLeft - 1)
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
