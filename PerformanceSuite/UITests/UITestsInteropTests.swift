import XCTest

final class UITestsInteropTests: XCTestCase {
    func testClearingStartupMessagesDoesNotReplayThemOnNextPoll() {
        let session = UUID()
        var history = UITestsInterop.MessageHistory()
        history.receive(.init(session: session, messages: [.startupHangStarted, .crashlyticsReady]))
        history.clearMessages()
        history.receive(.init(session: session, messages: [.startupHangStarted, .crashlyticsReady, .hangStarted]))

        XCTAssertEqual(history.messages, [.hangStarted])
    }

    func testRepeatedPollDoesNotDuplicateEvents() {
        let batch = UITestsInterop.MessageBatch(session: UUID(), messages: [.hangStarted, .nonFatalHang])
        var history = UITestsInterop.MessageHistory()

        history.receive(batch)
        history.receive(batch)

        XCTAssertEqual(history.messages, [.hangStarted, .nonFatalHang])
    }

    func testNextSnapshotRecoversEventsFromDroppedResponse() throws {
        let session = UUID()
        var history = UITestsInterop.MessageHistory()
        history.receive(.init(session: session, messages: [.hangStarted]))

        // The response containing the recovery event is lost. A subsequent poll
        // still includes it, even if another event has arrived in the meantime.
        let nextResponse = UITestsInterop.MessageBatch(
            session: session, messages: [.hangStarted, .nonFatalHang, .memoryLeak])
        let data = try JSONEncoder().encode(nextResponse)
        history.receive(try JSONDecoder().decode(UITestsInterop.MessageBatch.self, from: data))

        XCTAssertEqual(history.messages, [.hangStarted, .nonFatalHang, .memoryLeak])
    }

    func testRelaunchPreservesEarlierEventsAndAcceptsNewSession() {
        var history = UITestsInterop.MessageHistory()
        history.receive(.init(session: UUID(), messages: [.hangStarted, .nonFatalHang]))
        history.receive(.init(session: UUID(), messages: [.crash]))

        XCTAssertEqual(history.messages, [.hangStarted, .nonFatalHang, .crash])
    }

    func testDistinctEqualEventsAreNotDeduplicated() {
        let session = UUID()
        var history = UITestsInterop.MessageHistory()
        history.receive(.init(session: session, messages: [.appFreezeTime(duration: 10)]))
        history.receive(.init(session: session, messages: [
            .appFreezeTime(duration: 10), .appFreezeTime(duration: 20)
        ]))

        let durations = history.messages.compactMap { message -> Int? in
            guard case let .appFreezeTime(duration) = message else { return nil }
            return duration
        }
        XCTAssertEqual(durations, [10, 20])
    }
}
