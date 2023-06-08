//
//  HangsReporterTests.swift
//  PerformanceSuite-Tests
//
//  Created by Gleb Tarasov on 25/01/2022.
//

import XCTest

@testable import PerformanceSuite

//swiftlint:disable force_unwrapping
class HangReporterTests: XCTestCase {

    override func setUp() {
        super.setUp()
        self.continueAfterFailure = false
        PerformanceSuite.experiments = Experiments(ios_adq_no_locks_in_main_thread_call_stack: 1)
        #if arch(arm64)
            MainThreadCallStack.storeMainThread()
        #endif
    }

    override func tearDown() {
        super.tearDown()
        reporter = nil
        
        // Wait for hang reporter to be deallocated
        receiver.wait()
        
        PerformanceSuite.experiments = Experiments()
        
        receiver.fatalHang = nil
        receiver.hangInfo = nil
    }

    private let storage = StorageStub()
    private let receiver = HangReceiverStub()
    private let startupProvider = StartupTimeReporter(receiver: StartupTimeReceiverStub())
    private let detectionInterval = DispatchTimeInterval.milliseconds(5)
    private let hangThreshold = DispatchTimeInterval.milliseconds(40)
    private var reporter: HangReporter?

    var sleepInterval: TimeInterval {
        return 3 * (hangThreshold.timeInterval ?? 0)
    }

    func testNonFatalHang() {
        reporter = HangReporter(
            timeProvider: defaultTimeProvider,
            storage: storage,
            startupProvider: startupProvider,
            appStateProvider: AppStateProviderStub(),
            workingQueue: PerformanceSuite.queue,
            detectionTimerInterval: detectionInterval,
            hangThreshold: hangThreshold,
            enabledInDebug: true,
            receiver: receiver
        )
        XCTAssertNil(receiver.hangInfo)
        XCTAssertNil(receiver.fatalHang)

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
            workingQueue: PerformanceSuite.queue,
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
            XCTAssertTrue(value.contains("XCTestCore"))
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
            workingQueue: PerformanceSuite.queue,
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
            workingQueue: PerformanceSuite.queue,
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
            workingQueue: PerformanceSuite.queue,
            detectionTimerInterval: detectionInterval,
            hangThreshold: hangThreshold,
            enabledInDebug: true,
            receiver: receiver
        )

        // wait for all the queues
        PerformanceSuite.queue.sync {}
        PerformanceSuite.consumerQueue.sync {}

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
            workingQueue: PerformanceSuite.queue,
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

    func testHangInBackgroundIsNotReported() {
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
            workingQueue: PerformanceSuite.queue,
            detectionTimerInterval: detectionInterval,
            hangThreshold: hangThreshold,
            enabledInDebug: true,
            receiver: receiver
        )

        Thread.sleep(forTimeInterval: sleepInterval)
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

class HangReceiverStub: HangReceiver {
    var fatalHang: Bool?
    var hangInfo: HangInfo?

    func fatalHangReceived(info: HangInfo) {
        fatalHang = true
        self.hangInfo = info
    }

    func nonFatalHangReceived(info: HangInfo) {
        fatalHang = false
        self.hangInfo = info
    }

    func wait() {
        // wait for all the queues
        PerformanceSuite.queue.sync {}
        PerformanceSuite.consumerQueue.sync {}
        
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
        PerformanceSuite.queue.sync {}
        PerformanceSuite.consumerQueue.sync {}
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
