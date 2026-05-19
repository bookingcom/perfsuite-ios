//
//  MultiViewControllerLeaksReceiverTests.swift
//  PerformanceSuite-Tests
//
//  Created by Ahmed Nafei on 18/05/2026.
//

import UIKit
import XCTest
@testable import PerformanceSuite

final class MultiViewControllerLeaksReceiverTests: XCTestCase {

    private final class LeakStub: ViewControllerLeaksReceiver {
        var received: [ObjectIdentifier] = []
        func viewControllerLeakReceived(viewController: UIViewController) {
            received.append(ObjectIdentifier(viewController))
        }
    }

    func testFanOutToAllChildrenWhenShouldTrackIsNil() {
        let first = LeakStub()
        let second = LeakStub()
        let multi = MultiViewControllerLeaksReceiver(receivers: [first, second])
        let viewController = UIViewController()

        multi.viewControllerLeakReceived(viewController: viewController)

        XCTAssertEqual(first.received, [ObjectIdentifier(viewController)])
        XCTAssertEqual(second.received, [ObjectIdentifier(viewController)])
    }

    func testShouldTrackReturnsTrueByDefaultWhenNoPredicate() {
        let multi = MultiViewControllerLeaksReceiver(receivers: [LeakStub()])
        XCTAssertTrue(multi.shouldTrack(viewController: UIViewController()))
    }

    func testShouldTrackReturnsPredicateResultWhenSupplied() {
        let multi = MultiViewControllerLeaksReceiver(
            receivers: [LeakStub()],
            shouldTrack: { $0 is UINavigationController == false }
        )

        XCTAssertTrue(multi.shouldTrack(viewController: UIViewController()))
        XCTAssertFalse(multi.shouldTrack(viewController: UINavigationController()))
    }

    func testShouldTrackPredicateSuppressesDispatchToAllChildren() {
        let first = LeakStub()
        let second = LeakStub()
        let multi = MultiViewControllerLeaksReceiver(
            receivers: [first, second],
            shouldTrack: { _ in false }
        )

        multi.viewControllerLeakReceived(viewController: UIViewController())

        XCTAssertEqual(first.received, [], "Predicate returning false must suppress every child")
        XCTAssertEqual(second.received, [])
    }

    func testShouldTrackPredicateAppliedPerCallNotCachedAtInit() {
        // Predicate is invoked on every call so a stateful host predicate (e.g.
        // a feature-flag flip mid-session) takes effect immediately.
        var allow = false
        let stub = LeakStub()
        let multi = MultiViewControllerLeaksReceiver(
            receivers: [stub],
            shouldTrack: { _ in allow }
        )
        let viewController = UIViewController()

        multi.viewControllerLeakReceived(viewController: viewController)
        XCTAssertEqual(stub.received, [], "Disallowed: child must not see the leak")

        allow = true
        multi.viewControllerLeakReceived(viewController: viewController)
        XCTAssertEqual(stub.received, [ObjectIdentifier(viewController)])
    }

    func testOrderIsPreservedAcrossChildren() {
        var callOrder: [Int] = []

        final class OrderingStub: ViewControllerLeaksReceiver {
            let id: Int
            let onReceived: (Int) -> Void
            init(id: Int, onReceived: @escaping (Int) -> Void) {
                self.id = id
                self.onReceived = onReceived
            }
            func viewControllerLeakReceived(viewController: UIViewController) {
                onReceived(id)
            }
        }

        let multi = MultiViewControllerLeaksReceiver(receivers: [
            OrderingStub(id: 1, onReceived: { callOrder.append($0) }),
            OrderingStub(id: 2, onReceived: { callOrder.append($0) }),
            OrderingStub(id: 3, onReceived: { callOrder.append($0) }),
        ])

        multi.viewControllerLeakReceived(viewController: UIViewController())

        XCTAssertEqual(callOrder, [1, 2, 3])
    }

    func testEmptyReceiversArrayIsNoOp() {
        let multi = MultiViewControllerLeaksReceiver(receivers: [])

        XCTAssertTrue(multi.shouldTrack(viewController: UIViewController()))
        multi.viewControllerLeakReceived(viewController: UIViewController())
        // Should not crash. Nothing to assert on receivers — there are none.
    }

    func testEmptyReceiversArrayWithFalsePredicateIsNoOp() {
        let multi = MultiViewControllerLeaksReceiver(
            receivers: [],
            shouldTrack: { _ in false }
        )

        XCTAssertFalse(multi.shouldTrack(viewController: UIViewController()))
        multi.viewControllerLeakReceived(viewController: UIViewController())
    }
}
