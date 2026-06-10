//
//  HangReporterSessionIdTests.swift
//  PerformanceSuite-Tests
//
//  Created by Ahmed Nafei on 09/06/2026.
//

import XCTest

@testable import PerformanceSuite

/// Covers the `sessionIdProvider` plumbing on `HangReporter`: the closure is
/// invoked synchronously at hang detection and the returned value is stamped
/// onto `HangInfo.sessionId` for persistence and downstream emission.
final class HangReporterSessionIdTests: XCTestCase {

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
        receiver.wait()
        receiver.fatalHang = nil
        receiver.hangInfo = nil
        AppInfoHolder.resetForTests()
    }

    private let storage = StorageStub()
    private let receiver = HangsReceiverStub()
    private let startupProvider = StartupTimeReporter(receiver: SessionIdTestsStartupTimeReceiverStub())
    private let detectionInterval = DispatchTimeInterval.milliseconds(5)
    private let hangThreshold = DispatchTimeInterval.milliseconds(40)
    private var reporter: HangReporter?

    private var sleepInterval: TimeInterval {
        return 3 * (hangThreshold.timeInterval ?? 0)
    }

    /// When no provider is supplied, the `HangInfo` constructed at hang detection has
    /// `sessionId == nil`. Locks down the default behaviour for hosts that don't opt in.
    func testNilProviderResultsInNilSessionId() {
        reporter = HangReporter(
            timeProvider: defaultTimeProvider,
            storage: storage,
            startupProvider: startupProvider,
            appStateProvider: AppStateProviderStub(),
            workingQueue: PerformanceMonitoring.queue,
            detectionTimerInterval: detectionInterval,
            hangThreshold: hangThreshold,
            enabledInDebug: true,
            sessionIdProvider: nil,
            receiver: receiver
        )

        startupProvider.onViewDidLoadOfTheFirstViewController()
        startupProvider.onViewDidAppearOfTheFirstViewController()
        receiver.wait()
        receiver.wait()
        Thread.sleep(forTimeInterval: sleepInterval)
        receiver.wait()

        XCTAssertNotNil(receiver.hangInfo)
        XCTAssertNil(receiver.hangInfo?.sessionId)
    }

    /// The captured value is whatever the provider returns at *detection* time, not at reporter
    /// init time. A host whose session-id source rotates (e.g. on every foreground/background
    /// cycle) sees the live value reflected in the persisted `HangInfo`.
    func testProviderValueAtDetectionTimeWinsOverInitTimeValue() {
        let currentSessionId = AtomicSessionIdHolder(value: "session-init")
        reporter = HangReporter(
            timeProvider: defaultTimeProvider,
            storage: storage,
            startupProvider: startupProvider,
            appStateProvider: AppStateProviderStub(),
            workingQueue: PerformanceMonitoring.queue,
            detectionTimerInterval: detectionInterval,
            hangThreshold: hangThreshold,
            enabledInDebug: true,
            sessionIdProvider: { currentSessionId.value },
            receiver: receiver
        )

        // Rotate the session id between reporter init and the hang detection moment.
        currentSessionId.value = "session-after-rotation"

        startupProvider.onViewDidLoadOfTheFirstViewController()
        startupProvider.onViewDidAppearOfTheFirstViewController()
        receiver.wait()
        receiver.wait()
        Thread.sleep(forTimeInterval: sleepInterval)
        receiver.wait()

        XCTAssertEqual(receiver.hangInfo?.sessionId, "session-after-rotation")
    }

    /// A fatal hang persisted on the previous launch with a session id should round-trip the id
    /// through `Codable` storage and surface it on the receiver. End-to-end coverage of the
    /// pipeline: provider → HangInfo → storage → next-launch decode → receiver.
    func testPersistedFatalHangCarriesPreviousSessionId() {
        let timestamp = Date(timeIntervalSince1970: 1_700_000_000)
        storage.writeJSON(
            key: HangReporter.StorageKey.hangInfo,
            value: HangInfo.with(
                callStack: "previous-session stack",
                duringStartup: false,
                duration: .milliseconds(34),
                detectedAt: timestamp,
                sessionId: "previous-session-id"
            )
        )

        XCTAssertNil(receiver.hangInfo)

        reporter = HangReporter(
            timeProvider: defaultTimeProvider,
            storage: storage,
            startupProvider: startupProvider,
            appStateProvider: AppStateProviderStub(),
            workingQueue: PerformanceMonitoring.queue,
            detectionTimerInterval: detectionInterval,
            hangThreshold: hangThreshold,
            enabledInDebug: true,
            sessionIdProvider: { "current-session-id" },
            receiver: receiver
        )

        startupProvider.onViewDidLoadOfTheFirstViewController()
        startupProvider.onViewDidAppearOfTheFirstViewController()
        receiver.wait()

        XCTAssertEqual(receiver.fatalHang, true)
        XCTAssertEqual(receiver.hangInfo?.sessionId, "previous-session-id")
        XCTAssertEqual(receiver.hangInfo?.detectedAt, timestamp)
    }

    /// `HangInfo` constructed at hang detection has `detectedAt` populated with a wall-clock
    /// timestamp close to "now" — locks down the anchoring of the hang on the wall-clock
    /// timeline, so a fatal hang detected on the next launch carries the previous session's
    /// timestamp rather than the new launch's `now()`.
    func testDetectedAtIsPopulatedAtHangDetection() {
        let before = Date()

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
        receiver.wait()
        Thread.sleep(forTimeInterval: sleepInterval)
        receiver.wait()

        let after = Date()

        XCTAssertNotNil(receiver.hangInfo?.detectedAt)
        if let detectedAt = receiver.hangInfo?.detectedAt {
            XCTAssertGreaterThanOrEqual(detectedAt, before)
            XCTAssertLessThanOrEqual(detectedAt, after)
        }
    }
}

/// Tiny thread-safe holder used by tests that mutate the session-id source between reporter
/// init and hang detection. The hang reporter calls the provider on `PerformanceMonitoring.queue`,
/// so the read crosses a thread boundary; the holder serialises access through a lock.
private final class AtomicSessionIdHolder {
    private let lock = NSLock()
    private var _value: String?

    init(value: String?) {
        self._value = value
    }

    var value: String? {
        get {
            lock.lock()
            defer { lock.unlock() }
            return _value
        }
        set {
            lock.lock()
            defer { lock.unlock() }
            _value = newValue
        }
    }
}

private final class SessionIdTestsStartupTimeReceiverStub: StartupTimeReceiver {
    func startupTimeReceived(_ data: StartupTimeData) {}
}
