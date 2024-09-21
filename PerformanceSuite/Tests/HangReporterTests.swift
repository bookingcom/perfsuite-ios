//
//  HangsReporterTests.swift
//  PerformanceSuite-Tests
//
//  Created by Gleb Tarasov on 25/01/2022.
//

import XCTest

@testable import PerformanceSuite

class HangReporterTests: XCTestCase {

    override func setUp() {
        super.setUp()
        self.continueAfterFailure = false
        #if arch(arm64)
            MainThreadCallStack.storeMainThread()
        #endif
    }

    override func tearDown() {
        super.tearDown()
        reporter = nil

        // Wait for hang reporter to be deallocated
        receiver.wait()

        receiver.fatalHang = nil
        receiver.hangInfo = nil
        AppInfoHolder.resetForTests()
    }

    private let storage = StorageStub()
    private let receiver = HangsReceiverStub()
    private let startupProvider = StartupTimeReporter(receiver: StartupTimeReceiverStub())
    private let detectionInterval = DispatchTimeInterval.milliseconds(5)
    private let hangThreshold = DispatchTimeInterval.milliseconds(40)
    private var reporter: HangReporter?

    var sleepInterval: TimeInterval {
        return 3 * (hangThreshold.timeInterval ?? 0)
    }

    func testHangStarted() {
        reporter = HangReporter(
            timeProvider: defaultTimeProvider,
            storage: storage,
            startupProvider: startupProvider,
            appStateProvider: AppStateProviderStub(),
            workingQueue: PerformanceMonitoring.queue,
            detectionTimerInterval: detectionInterval,
            hangThreshold: hangThreshold,
            enabledInDebug: true,
            receiver: receiver
        )
        XCTAssertNil(receiver.hangInfo)
        XCTAssertNil(receiver.fatalHang)
        XCTAssertNil(receiver.hangJustStarted)

        receiver.wait()

        let exp = expectation(description: "wait background thread")
        DispatchQueue.global().async {
            Thread.sleep(forTimeInterval: self.sleepInterval / 2)
            PerformanceMonitoring.queue.sync {}
            PerformanceMonitoring.consumerQueue.sync {}
            // we should detect that hang started
            XCTAssertEqual(self.receiver.hangJustStarted, true)
            XCTAssertNotNil(self.receiver.hangInfo)

            Thread.sleep(forTimeInterval: self.sleepInterval)
            PerformanceMonitoring.queue.sync {}
            PerformanceMonitoring.consumerQueue.sync {}

            // hang finished
            XCTAssertEqual(self.receiver.hangJustStarted, nil)
            XCTAssertNotNil(self.receiver.hangInfo)

            exp.fulfill()
        }
        Thread.sleep(forTimeInterval: sleepInterval)
        wait(for: [exp], timeout: 1)
    }

    func testNonFatalHang() {
        reporter = HangReporter(
            timeProvider: defaultTimeProvider,
            storage: storage,
            startupProvider: startupProvider,
            appStateProvider: AppStateProviderStub(),
            workingQueue: PerformanceMonitoring.queue,
            detectionTimerInterval: detectionInterval,
            hangThreshold: hangThreshold,
            enabledInDebug: true,
            receiver: receiver
        )
        XCTAssertNil(receiver.hangInfo)
        XCTAssertNil(receiver.fatalHang)
        XCTAssertNil(receiver.hangJustStarted)

        startupProvider.onViewDidLoadOfTheFirstViewController()
        startupProvider.onViewDidAppearOfTheFirstViewController()
        receiver.wait()

        // hang reporter checks app state on the main thread, so we should skip one run loop here
        receiver.wait()
        Thread.sleep(forTimeInterval: sleepInterval)
        receiver.wait()

        XCTAssertNotNil(receiver.hangInfo)
        #if arch(arm64)
            XCTAssertTrue(receiver.hangInfo!.callStack.contains("XCTestCore"))
        #endif
        XCTAssertNil(receiver.hangJustStarted)
        XCTAssertEqual(receiver.fatalHang, false)
        XCTAssertGreaterThan(receiver.hangInfo!.duration.timeInterval!, hangThreshold.timeInterval!)
        XCTAssertFalse(receiver.hangInfo!.duringStartup)

        let callStack: String? = storage.read(key: HangReporter.StorageKey.hangInfo)
        XCTAssertNil(callStack)
    }

    func testStartupNonFatalHang() {
        reporter = HangReporter(
            timeProvider: defaultTimeProvider,
            storage: storage,
            startupProvider: startupProvider,
            appStateProvider: AppStateProviderStub(),
            workingQueue: PerformanceMonitoring.queue,
            detectionTimerInterval: detectionInterval,
            hangThreshold: hangThreshold,
            enabledInDebug: true,
            receiver: receiver
        )
        XCTAssertNil(receiver.hangInfo)
        XCTAssertNil(receiver.fatalHang)

        receiver.wait()
        Thread.sleep(forTimeInterval: sleepInterval)
        receiver.wait()

        XCTAssertNotNil(receiver.hangInfo)
        #if arch(arm64)
            XCTAssertTrue(receiver.hangInfo!.callStack.contains("XCTestCore"))
        #else
            XCTAssertEqual(receiver.hangInfo!.callStack, "")
        #endif
        XCTAssertEqual(receiver.fatalHang, false)
        XCTAssertTrue(receiver.hangInfo!.duringStartup)
        XCTAssertGreaterThan(receiver.hangInfo!.duration.timeInterval!, hangThreshold.timeInterval!)

        let callStack: String? = storage.read(key: HangReporter.StorageKey.hangInfo)
        XCTAssertNil(callStack)
    }

    func testHangDetectedFired() {
        let exp = expectation(description: "storage fired")
        var fullfilled = false
        let storage = StorageStubWithBlock(key: "hangInfo") { value in
            guard let value = value else {
                return
            }
            #if arch(arm64)
                XCTAssertTrue(value.contains("XCTestCore"))
            #else
                XCTAssertTrue(value.contains("\"callStack\":\"\""))
            #endif
            if !fullfilled {
                exp.fulfill()
                fullfilled = true
            }
        }
        reporter = HangReporter(
            timeProvider: defaultTimeProvider,
            storage: storage,
            startupProvider: startupProvider,
            appStateProvider: AppStateProviderStub(),
            workingQueue: PerformanceMonitoring.queue,
            detectionTimerInterval: detectionInterval,
            hangThreshold: hangThreshold,
            enabledInDebug: true,
            receiver: receiver
        )

        startupProvider.onViewDidLoadOfTheFirstViewController()
        startupProvider.onViewDidAppearOfTheFirstViewController()
        receiver.wait()


        Thread.sleep(forTimeInterval: sleepInterval)
        wait(for: [exp], timeout: 1)
    }

    func testFatalHang() {
        storage.writeJSON(
            key: HangReporter.StorageKey.hangInfo,
            value: HangInfo.with(callStack: "perfect call stack", duringStartup: false, duration: .milliseconds(34)))

        XCTAssertNil(receiver.hangInfo)
        XCTAssertNil(receiver.fatalHang)

        reporter = HangReporter(
            timeProvider: defaultTimeProvider,
            storage: storage,
            startupProvider: startupProvider,
            appStateProvider: AppStateProviderStub(),
            workingQueue: PerformanceMonitoring.queue,
            detectionTimerInterval: detectionInterval,
            hangThreshold: hangThreshold,
            enabledInDebug: true,
            receiver: receiver
        )

        startupProvider.onViewDidLoadOfTheFirstViewController()
        startupProvider.onViewDidAppearOfTheFirstViewController()
        receiver.wait()

        XCTAssertEqual(receiver.fatalHang, true)
        XCTAssertNotNil(receiver.hangInfo)
        XCTAssertEqual(receiver.hangInfo!.duringStartup, false)
        XCTAssertEqual(receiver.hangInfo!.duration, DispatchTimeInterval.milliseconds(34))
        #if arch(arm64)
            XCTAssertEqual(receiver.hangInfo!.callStack, "perfect call stack")
        #endif
    }

    func testStartupFatalHang() {
        storage.writeJSON(
            key: HangReporter.StorageKey.hangInfo,
            value: HangInfo.with(callStack: "one more perfect call stack", duringStartup: true, duration: .milliseconds(3435)))

        XCTAssertNil(receiver.hangInfo)
        XCTAssertNil(receiver.fatalHang)

        reporter = HangReporter(
            timeProvider: defaultTimeProvider,
            storage: storage,
            startupProvider: startupProvider,
            appStateProvider: AppStateProviderStub(),
            workingQueue: PerformanceMonitoring.queue,
            detectionTimerInterval: detectionInterval,
            hangThreshold: hangThreshold,
            enabledInDebug: true,
            receiver: receiver
        )

        // wait for all the queues
        PerformanceMonitoring.queue.sync {}
        PerformanceMonitoring.consumerQueue.sync {}

        XCTAssertEqual(receiver.fatalHang, true)
        XCTAssertNotNil(receiver.hangInfo)
        XCTAssert(receiver.hangInfo!.iOSVersion.contains("."))
        XCTAssertEqual(receiver.hangInfo!.duringStartup, true)
        XCTAssertEqual(receiver.hangInfo!.duration.milliseconds, 3435)
        #if arch(arm64)
            XCTAssertEqual(receiver.hangInfo!.callStack, "one more perfect call stack")
            XCTAssert(receiver.hangInfo!.architecture.hasPrefix("arm64"))
        #endif
    }

    func testStartupFatalHangDetectedIfMainThreadIsBlockedImmediately() {
        var hangInfo: HangInfo?
        hangInfo = storage.readJSON(key: HangReporter.StorageKey.hangInfo)
        XCTAssertNil(hangInfo)

        reporter = HangReporter(
            timeProvider: defaultTimeProvider,
            storage: storage,
            startupProvider: startupProvider,
            appStateProvider: AppStateProviderStub(),
            workingQueue: PerformanceMonitoring.queue,
            detectionTimerInterval: detectionInterval,
            hangThreshold: hangThreshold,
            enabledInDebug: true,
            receiver: receiver
        )

        Thread.sleep(forTimeInterval: sleepInterval)

        hangInfo = storage.readJSON(key: HangReporter.StorageKey.hangInfo)
        XCTAssertNotNil(hangInfo)
        XCTAssertTrue(hangInfo!.duringStartup)
    }

    func testStartupFatalHangDetectedIfMainThreadIsBlockedAfterSomeTime() {
        var hangInfo: HangInfo?
        hangInfo = storage.readJSON(key: HangReporter.StorageKey.hangInfo)
        XCTAssertNil(hangInfo)

        reporter = HangReporter(
            timeProvider: defaultTimeProvider,
            storage: storage,
            startupProvider: startupProvider,
            appStateProvider: AppStateProviderStub(),
            workingQueue: PerformanceMonitoring.queue,
            detectionTimerInterval: detectionInterval,
            hangThreshold: hangThreshold,
            enabledInDebug: true,
            receiver: receiver
        )

        wait(milliseconds: 30)
        Thread.sleep(forTimeInterval: sleepInterval)

        hangInfo = storage.readJSON(key: HangReporter.StorageKey.hangInfo)
        XCTAssertNotNil(hangInfo)
        XCTAssertTrue(hangInfo!.duringStartup)
    }

    func testCrashIsNotReportedAsHang() {
        storage.writeJSON(
            key: HangReporter.StorageKey.hangInfo,
            value: HangInfo.with(callStack: "perfect call stack", duringStartup: false, duration: .milliseconds(34)))

        XCTAssertNil(receiver.hangInfo)
        XCTAssertNil(receiver.fatalHang)

        reporter = HangReporter(
            timeProvider: defaultTimeProvider,
            storage: storage,
            startupProvider: startupProvider,
            appStateProvider: AppStateProviderStub(),
            workingQueue: PerformanceMonitoring.queue,
            detectionTimerInterval: detectionInterval,
            hangThreshold: hangThreshold,
            didCrashPreviously: true,
            enabledInDebug: true,
            receiver: receiver
        )

        startupProvider.onViewDidLoadOfTheFirstViewController()
        startupProvider.onViewDidAppearOfTheFirstViewController()
        receiver.wait()

        XCTAssertNil(receiver.fatalHang)
        XCTAssertNil(receiver.hangInfo)
    }

    func testHangReporterStartedInBackgroundIsNotReportingHangs() {
        XCTAssertNil(receiver.hangInfo)
        XCTAssertNil(receiver.fatalHang)
        let appStateProvider = AppStateProviderStub()
        appStateProvider.applicationState = .background

        let storage = StorageStubWithBlock(key: "hangInfo") { value in
            if value != nil {
                XCTFail("Hang shouldn't be detected when app is in background")
            }
        }

        reporter = HangReporter(
            timeProvider: defaultTimeProvider,
            storage: storage,
            startupProvider: startupProvider,
            appStateProvider: appStateProvider,
            workingQueue: PerformanceMonitoring.queue,
            detectionTimerInterval: detectionInterval,
            hangThreshold: hangThreshold,
            enabledInDebug: true,
            receiver: receiver
        )

        wait(milliseconds: 50)
        Thread.sleep(forTimeInterval: sleepInterval)
    }

    func testHangInBackgroundIsNotReported() {
        XCTAssertNil(receiver.hangInfo)
        XCTAssertNil(receiver.fatalHang)
        let appStateProvider = AppStateProviderStub()

        let storage = StorageStubWithBlock(key: "hangInfo") { value in
            if value != nil {
                XCTFail("Hang shouldn't be detected when app is in background")
            }
        }

        reporter = HangReporter(
            timeProvider: defaultTimeProvider,
            storage: storage,
            startupProvider: startupProvider,
            appStateProvider: appStateProvider,
            workingQueue: PerformanceMonitoring.queue,
            detectionTimerInterval: detectionInterval,
            hangThreshold: hangThreshold,
            enabledInDebug: true,
            receiver: receiver
        )

        wait(milliseconds: 50)
        NotificationCenter.default.post(name: UIApplication.willResignActiveNotification, object: nil)
        wait(milliseconds: 50)
        Thread.sleep(forTimeInterval: sleepInterval)
    }

    func testHangAfterDidBecomeActiveIsReported() {
        XCTAssertNil(receiver.hangInfo)
        XCTAssertNil(receiver.fatalHang)
        let appStateProvider = AppStateProviderStub()

        let exp = expectation(description: "storage fired")
        var fullfilled = false
        let storage = StorageStubWithBlock(key: "hangInfo") { value in
            guard let value = value else {
                return
            }
#if arch(arm64)
            XCTAssertTrue(value.contains("XCTestCore"))
#else
            XCTAssertTrue(value.contains("\"callStack\":\"\""))
#endif
            if !fullfilled {
                exp.fulfill()
                fullfilled = true
            }
        }

        reporter = HangReporter(
            timeProvider: defaultTimeProvider,
            storage: storage,
            startupProvider: startupProvider,
            appStateProvider: appStateProvider,
            workingQueue: PerformanceMonitoring.queue,
            detectionTimerInterval: detectionInterval,
            hangThreshold: hangThreshold,
            enabledInDebug: true,
            receiver: receiver
        )

        wait(milliseconds: 50)
        NotificationCenter.default.post(name: UIApplication.willResignActiveNotification, object: nil)
        wait(milliseconds: 50)
        NotificationCenter.default.post(name: UIApplication.didBecomeActiveNotification, object: nil)
        wait(milliseconds: 50)
        Thread.sleep(forTimeInterval: sleepInterval)
        wait(for: [exp], timeout: 1)
    }


    func testHangReporterIsNotStartedWhenAppPrewarmed() {
        XCTAssertNil(receiver.hangInfo)
        XCTAssertNil(receiver.fatalHang)
        let appStateProvider = AppStateProviderStub()

        // emulate prewarming
        setenv("ActivePrewarm", "1", 1)
        AppInfoHolder.recordMainStarted()

        let exp = expectation(description: "storage fired")
        var fullfilled = false
        let storage = StorageStubWithBlock(key: "hangInfo") { value in
            guard let value = value else {
                return
            }
#if arch(arm64)
            XCTAssertTrue(value.contains("XCTestCore"))
#else
            XCTAssertTrue(value.contains("\"callStack\":\"\""))
#endif
            if !fullfilled {
                exp.fulfill()
                fullfilled = true
            }
        }

        reporter = HangReporter(
            timeProvider: defaultTimeProvider,
            storage: storage,
            startupProvider: startupProvider,
            appStateProvider: appStateProvider,
            workingQueue: PerformanceMonitoring.queue,
            detectionTimerInterval: detectionInterval,
            hangThreshold: hangThreshold,
            enabledInDebug: true,
            receiver: receiver
        )

        wait(milliseconds: 50)

        NotificationCenter.default.post(name: UIApplication.didBecomeActiveNotification, object: nil)

        Thread.sleep(forTimeInterval: sleepInterval)

        wait(for: [exp], timeout: 1)

        setenv("ActivePrewarm", "", 1)
    }

    func testHangReporterIsStartedWhenAppPrewarmedAfterDidBecomeActive() {
        XCTAssertNil(receiver.hangInfo)
        XCTAssertNil(receiver.fatalHang)
        let appStateProvider = AppStateProviderStub()

        // emulate prewarming
        setenv("ActivePrewarm", "1", 1)
        AppInfoHolder.recordMainStarted()

        let storage = StorageStubWithBlock(key: "hangInfo") { value in
            if value != nil {
                XCTFail("Hang shouldn't be detected when app is in background")
            }
        }

        reporter = HangReporter(
            timeProvider: defaultTimeProvider,
            storage: storage,
            startupProvider: startupProvider,
            appStateProvider: appStateProvider,
            workingQueue: PerformanceMonitoring.queue,
            detectionTimerInterval: detectionInterval,
            hangThreshold: hangThreshold,
            enabledInDebug: true,
            receiver: receiver
        )

        wait(milliseconds: 50)
        Thread.sleep(forTimeInterval: sleepInterval)

        setenv("ActivePrewarm", "", 1)
    }

    private func wait(milliseconds: Int) {
        let exp = expectation(description: "wait")
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(milliseconds)) {
            exp.fulfill()
        }

        wait(for: [exp], timeout: TimeInterval(milliseconds * 1000 + 1))
    }
}

private class StorageStubWithBlock: Storage {
    init(key: String, block: @escaping (String?) -> Void) {
        self.key = key
        self.block = block
    }
    private let key: String
    private let block: (String?) -> Void

    func read(domain: String, key: String) -> String? {
        return nil
    }

    func write(domain: String, key: String, value: String?) {
        if key == self.key {
            block(value)
        }
    }
}

class HangsReceiverStub: HangsReceiver {
    var fatalHang: Bool?
    var hangJustStarted: Bool?
    var hangInfo: HangInfo?

    func hangStarted(info: HangInfo) {
        hangJustStarted = true
        hangInfo = info
    }

    func fatalHangReceived(info: HangInfo) {
        hangJustStarted = nil
        fatalHang = true
        hangInfo = info
    }

    func nonFatalHangReceived(info: HangInfo) {
        hangJustStarted = nil
        fatalHang = false
        hangInfo = info
    }

    func wait() {
        // wait for all the queues
        PerformanceMonitoring.queue.sync {}
        PerformanceMonitoring.consumerQueue.sync {}

        // skip one run loop
        let exp = XCTestExpectation(description: "run loop")
        DispatchQueue.global().async {
            DispatchQueue.main.async {
                exp.fulfill()
            }
        }
        let waiter = XCTWaiter()
        waiter.wait(for: [exp], timeout: 1)

        // and again wait for all the queues
        PerformanceMonitoring.queue.sync {}
        PerformanceMonitoring.consumerQueue.sync {}
    }
}

class AppStateProviderStub: AppStateProvider {
    var applicationState: UIApplication.State = .active
}

class StartupProviderStub: StartupProvider {
    var appIsStarting: Bool = true
    var actions: [() -> Void] = []
    private let syncQueue = DispatchQueue(label: "StartupProviderStub")

    func notifyAfterAppStarted(_ action: @escaping () -> Void) {
        let isStarting = syncQueue.sync {
            appIsStarting
        }

        if isStarting {
            syncQueue.sync {
                actions.append(action)
            }
        } else {
            action()
        }
    }

    func appStarted() {
        let acts = syncQueue.sync {
            appIsStarting = false
            return actions
        }
        acts.forEach {
            $0()
        }
    }
}


private class StartupTimeReceiverStub: StartupTimeReceiver {
    func startupTimeReceived(_ data: StartupTimeData) {
    }
}
