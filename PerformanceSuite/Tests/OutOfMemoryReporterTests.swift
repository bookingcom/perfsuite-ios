//
//  OutOfMemoryReporterTests.swift
//  PerformanceSuite-Tests
//
//  Created by Gleb Tarasov on 25/01/2022.
//

import XCTest

@testable import PerformanceSuite

// swiftlint:disable force_unwrapping
class OutOfMemoryReporterTests: XCTestCase {

    override func tearDown() {
        super.tearDown()
        storage.clear()
        receiver.oomData = nil
    }

    private let storage = StorageStub()
    private let receiver = OutOfMemoryReceiverStub()

    func testTheFirstLaunch() {
        _ = OutOfMemoryReporter(storage: storage, enabledInDebug: true, receiver: receiver)
        receiver.wait()
        XCTAssertNil(receiver.oomData)
    }

    func testOOMDetection() {
        // first launch
        var reporter = OutOfMemoryReporter(storage: storage, enabledInDebug: true, receiver: receiver)
        receiver.wait()
        NotificationCenter.default.post(name: UIApplication.didReceiveMemoryWarningNotification, object: nil)
        NotificationCenter.default.post(name: UIApplication.didReceiveMemoryWarningNotification, object: nil)
        receiver.wait()
        XCTAssertNil(receiver.oomData)
        // forbid reporter to release until this
        _ = reporter

        // second launch, OOM should be detected
        reporter = OutOfMemoryReporter(storage: storage, enabledInDebug: true, receiver: receiver)
        receiver.wait()
        XCTAssertNotNil(receiver.oomData)

        XCTAssertEqual(receiver.oomData?.memoryWarnings, 2)
    }

    func testSystemRebooted() {
        // first launch
        _ = OutOfMemoryReporter(storage: storage, enabledInDebug: true, receiver: receiver)
        receiver.wait()
        XCTAssertNil(receiver.oomData)

        // second launch, but after system reboot
        let currentUptime = ProcessInfo.processInfo.systemUptime
        storage.write(key: OutOfMemoryReporter.StorageKey.systemRebootTime, value: currentUptime - 1000)
        _ = OutOfMemoryReporter(storage: storage, enabledInDebug: true, receiver: receiver)
        receiver.wait()
        XCTAssertNil(receiver.oomData)
    }

    func testLanguageChanged() {
        // first launch
        _ = OutOfMemoryReporter(storage: storage, enabledInDebug: true, receiver: receiver)
        receiver.wait()
        XCTAssertNil(receiver.oomData)

        // second launch with the changed app language, no OOM
        storage.write(key: OutOfMemoryReporter.StorageKey.preferredLocalizations, value: "")
        _ = OutOfMemoryReporter(storage: storage, enabledInDebug: true, receiver: receiver)
        receiver.wait()
        XCTAssertNil(receiver.oomData)

        // third launch with the changed system language, no OOM
        storage.write(key: OutOfMemoryReporter.StorageKey.preferredLanguages, value: "")
        _ = OutOfMemoryReporter(storage: storage, enabledInDebug: true, receiver: receiver)
        receiver.wait()
        XCTAssertNil(receiver.oomData)
    }

    func testAppCrashed() {
        // first launch
        _ = OutOfMemoryReporter(storage: storage, enabledInDebug: true, receiver: receiver)
        receiver.wait()
        XCTAssertNil(receiver.oomData)

        // second launch after the crash, no OOM
        _ = OutOfMemoryReporter(storage: storage, didCrashPreviously: true, enabledInDebug: true, receiver: receiver)
        receiver.wait()
        XCTAssertNil(receiver.oomData)
    }

    func testFatalHangHappened() {
        // first launch
        _ = OutOfMemoryReporter(storage: storage, enabledInDebug: true, receiver: receiver)
        receiver.wait()
        XCTAssertNil(receiver.oomData)

        // second launch after the crash, no OOM
        _ = OutOfMemoryReporter(
            storage: storage, didHangPreviouslyProvider: DidHangPreviouslyProviderStub(), enabledInDebug: true, receiver: receiver)
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
        var reporter = OutOfMemoryReporter(storage: storage, enabledInDebug: true, receiver: receiver)
        receiver.wait()
        NotificationCenter.default.post(name: UIApplication.willTerminateNotification, object: nil)
        receiver.wait()
        XCTAssertNil(receiver.oomData)
        // forbid to deallocate
        _ = reporter

        // second launch after app was terminated, no OOM
        reporter = OutOfMemoryReporter(storage: storage, enabledInDebug: true, receiver: receiver)
        receiver.wait()
        XCTAssertNil(receiver.oomData)
    }

    func testAppUpdated() {
        // first launch
        _ = OutOfMemoryReporter(storage: storage, enabledInDebug: true, receiver: receiver)
        receiver.wait()
        XCTAssertNil(receiver.oomData)

        // second launch, but after app update, no OOM
        storage.write(key: OutOfMemoryReporter.StorageKey.bundleVersion, value: "9.9.9")
        _ = OutOfMemoryReporter(storage: storage, enabledInDebug: true, receiver: receiver)
        receiver.wait()
        XCTAssertNil(receiver.oomData)
    }

    func testTimezoneChangeDoesntAffectSystemUptime() {
        let cachedTimeZone = NSTimeZone.default

        NSTimeZone.default = TimeZone(secondsFromGMT: 3600)!
        // first launch
        _ = OutOfMemoryReporter(storage: storage, enabledInDebug: true, receiver: receiver)
        receiver.wait()
        XCTAssertNil(receiver.oomData)

        // second launch, but after timezone changed,
        // OOM should be detected, since systemRebootTime hasn't changed, only timezone changed
        NSTimeZone.default = TimeZone(secondsFromGMT: -3600)!
        _ = OutOfMemoryReporter(storage: storage, enabledInDebug: true, receiver: receiver)
        receiver.wait()
        XCTAssertNotNil(receiver.oomData)

        // third launch, after timezone changed back,
        // OOM should be detected, since systemRebootTime hasn't changed, only timezone changed
        NSTimeZone.default = TimeZone(secondsFromGMT: 3600)!

        _ = OutOfMemoryReporter(storage: storage, enabledInDebug: true, receiver: receiver)
        receiver.wait()
        XCTAssertNotNil(receiver.oomData)

        NSTimeZone.default = cachedTimeZone
    }
}

class OutOfMemoryReceiverStub: OutOfMemoryReceiver {

    var oomData: OOMData?

    func outOfMemoryTerminationReceived(_ data: OOMData) {
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

        PerformanceSuite.queue.sync {}
        PerformanceSuite.consumerQueue.sync {}
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
