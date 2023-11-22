//
//  WatchdogTerminationReporterTests.swift
//  PerformanceSuite-Tests
//
//  Created by Gleb Tarasov on 25/01/2022.
//

import XCTest

@testable import PerformanceSuite

// swiftlint:disable force_unwrapping
class WatchdogTerminationReporterTests: XCTestCase {

    override func setUp() {
        super.setUp()
        AppInfoHolder.resetForTests()
    }

    override func tearDown() {
        super.tearDown()
        storage.clear()
        receiver.oomData = nil
    }

    private let storage = StorageStub()
    private let receiver = WatchdogTerminationsReceiverStub()
    private let startupProvider = StartupProviderStub()

    func testTheFirstLaunch() {
        _ = WatchdogTerminationReporter(storage: storage, startupProvider: startupProvider, enabledInDebug: true, receiver: receiver)
        receiver.wait()
        XCTAssertNil(receiver.oomData)
    }

    func testOOMDetection() {
        // first launch
        startupProvider.appStarted()
        var reporter = WatchdogTerminationReporter(storage: storage, startupProvider: startupProvider, enabledInDebug: true, receiver: receiver)
        receiver.wait()
        NotificationCenter.default.post(name: UIApplication.didReceiveMemoryWarningNotification, object: nil)
        NotificationCenter.default.post(name: UIApplication.didReceiveMemoryWarningNotification, object: nil)
        receiver.wait()
        XCTAssertNil(receiver.oomData)
        // forbid reporter to release until this
        _ = reporter

        // second launch, OOM should be detected
        reporter = WatchdogTerminationReporter(storage: storage, startupProvider: startupProvider, enabledInDebug: true, receiver: receiver)
        receiver.wait()
        XCTAssertNotNil(receiver.oomData)

        XCTAssertEqual(receiver.oomData?.memoryWarnings, 2)
        XCTAssertEqual(receiver.oomData?.duringStartup, false)
        XCTAssertEqual(receiver.oomData?.appStartInfo?.appStartedWithPrewarming, false)
    }

    func testPrewarmingDuringStartup() {
        setenv("ActivePrewarm", "1", 1)
        AppInfoHolder.recordMainStarted()

        // first launch
        var reporter = WatchdogTerminationReporter(storage: storage, startupProvider: startupProvider, enabledInDebug: true, receiver: receiver)
        receiver.wait()
        _ = reporter

        // second launch, OOM should be detected
        reporter = WatchdogTerminationReporter(storage: storage, startupProvider: startupProvider, enabledInDebug: true, receiver: receiver)
        receiver.wait()
        XCTAssertNotNil(receiver.oomData)
        XCTAssertEqual(receiver.oomData?.duringStartup, true)
        XCTAssertEqual(receiver.oomData?.appStartInfo?.appStartedWithPrewarming, true)

        setenv("ActivePrewarm", "", 1)
    }

    func testSystemRebooted() {
        // first launch
        _ = WatchdogTerminationReporter(storage: storage, startupProvider: startupProvider, enabledInDebug: true, receiver: receiver)
        receiver.wait()
        XCTAssertNil(receiver.oomData)

        // second launch, but after system reboot
        let currentUptime = ProcessInfo.processInfo.systemUptime
        storage.write(key: WatchdogTerminationReporter.StorageKey.systemRebootTime, value: currentUptime - 1000)
        _ = WatchdogTerminationReporter(storage: storage, startupProvider: startupProvider, enabledInDebug: true, receiver: receiver)
        receiver.wait()
        XCTAssertNil(receiver.oomData)
    }

    func testLanguageChanged() {
        // first launch
        _ = WatchdogTerminationReporter(storage: storage, startupProvider: startupProvider, enabledInDebug: true, receiver: receiver)
        receiver.wait()
        XCTAssertNil(receiver.oomData)

        // second launch with the changed app language, no OOM
        storage.write(key: WatchdogTerminationReporter.StorageKey.preferredLocalizations, value: "")
        _ = WatchdogTerminationReporter(storage: storage, startupProvider: startupProvider, enabledInDebug: true, receiver: receiver)
        receiver.wait()
        XCTAssertNil(receiver.oomData)

        // third launch with the changed system language, no OOM
        storage.write(key: WatchdogTerminationReporter.StorageKey.preferredLanguages, value: "")
        _ = WatchdogTerminationReporter(storage: storage, startupProvider: startupProvider, enabledInDebug: true, receiver: receiver)
        receiver.wait()
        XCTAssertNil(receiver.oomData)
    }

    func testAppCrashed() {
        // first launch
        _ = WatchdogTerminationReporter(storage: storage, startupProvider: startupProvider, enabledInDebug: true, receiver: receiver)
        receiver.wait()
        XCTAssertNil(receiver.oomData)

        // second launch after the crash, no OOM
        _ = WatchdogTerminationReporter(storage: storage, didCrashPreviously: true, startupProvider: startupProvider, enabledInDebug: true, receiver: receiver)
        receiver.wait()
        XCTAssertNil(receiver.oomData)
    }

    func testFatalHangHappened() {
        // first launch
        _ = WatchdogTerminationReporter(storage: storage, startupProvider: startupProvider, enabledInDebug: true, receiver: receiver)
        receiver.wait()
        XCTAssertNil(receiver.oomData)

        // second launch after the crash, no OOM
        _ = WatchdogTerminationReporter(
            storage: storage, didHangPreviouslyProvider: DidHangPreviouslyProviderStub(), startupProvider: startupProvider, enabledInDebug: true, receiver: receiver)
        receiver.wait()
        XCTAssertNil(receiver.oomData)
    }

    private class DidHangPreviouslyProviderStub: DidHangPreviouslyProvider {
        func didHangPreviously() -> Bool {
            return true
        }
    }

    func testAppWasTerminated() {
        // first launch
        var reporter = WatchdogTerminationReporter(storage: storage, startupProvider: startupProvider, enabledInDebug: true, receiver: receiver)
        receiver.wait()
        NotificationCenter.default.post(name: UIApplication.willTerminateNotification, object: nil)
        receiver.wait()
        XCTAssertNil(receiver.oomData)
        // forbid to deallocate
        _ = reporter

        // second launch after app was terminated, no OOM
        reporter = WatchdogTerminationReporter(storage: storage, startupProvider: startupProvider, enabledInDebug: true, receiver: receiver)
        receiver.wait()
        XCTAssertNil(receiver.oomData)
    }

    func testAppUpdated() {
        // first launch
        _ = WatchdogTerminationReporter(storage: storage, startupProvider: startupProvider, enabledInDebug: true, receiver: receiver)
        receiver.wait()
        XCTAssertNil(receiver.oomData)

        // second launch, but after app update, no OOM
        storage.write(key: WatchdogTerminationReporter.StorageKey.bundleVersion, value: "9.9.9")
        _ = WatchdogTerminationReporter(storage: storage, startupProvider: startupProvider, enabledInDebug: true, receiver: receiver)
        receiver.wait()
        XCTAssertNil(receiver.oomData)
    }

    func testTimezoneChangeDoesntAffectSystemUptime() {
        let cachedTimeZone = NSTimeZone.default

        NSTimeZone.default = TimeZone(secondsFromGMT: 3600)!
        // first launch
        _ = WatchdogTerminationReporter(storage: storage, startupProvider: startupProvider, enabledInDebug: true, receiver: receiver)
        receiver.wait()
        XCTAssertNil(receiver.oomData)

        // second launch, but after timezone changed,
        // OOM should be detected, since systemRebootTime hasn't changed, only timezone changed
        NSTimeZone.default = TimeZone(secondsFromGMT: -3600)!
        _ = WatchdogTerminationReporter(storage: storage, startupProvider: startupProvider, enabledInDebug: true, receiver: receiver)
        receiver.wait()
        XCTAssertNotNil(receiver.oomData)

        // third launch, after timezone changed back,
        // OOM should be detected, since systemRebootTime hasn't changed, only timezone changed
        NSTimeZone.default = TimeZone(secondsFromGMT: 3600)!

        _ = WatchdogTerminationReporter(storage: storage, startupProvider: startupProvider, enabledInDebug: true, receiver: receiver)
        receiver.wait()
        XCTAssertNotNil(receiver.oomData)

        NSTimeZone.default = cachedTimeZone
    }
}

class WatchdogTerminationsReceiverStub: WatchdogTerminationsReceiver {

    var oomData: WatchdogTerminationData?

    func watchdogTerminationReceived(_ data: WatchdogTerminationData) {
        oomData = data
    }

    func wait() {
        // skip one run loop
        let exp = XCTestExpectation(description: "run loop")
        DispatchQueue.main.async {
            exp.fulfill()
        }
        let waiter = XCTWaiter()
        waiter.wait(for: [exp], timeout: 1)

        PerformanceMonitoring.queue.sync {}
        PerformanceMonitoring.consumerQueue.sync {}
    }
}

class StorageStub: Storage {
    var storage: [String: String] = [:]
    func write(domain: String, key: String, value: String?) {
        storage[key] = value
    }
    func read(domain: String, key: String) -> String? {
        return storage[key]
    }
    func clear() {
        storage = [:]
    }
}
