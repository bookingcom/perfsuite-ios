//
//  ViewControllerLeaksReceiverDefaultsTests.swift
//  PerformanceSuite-Tests
//
//  Created by Ahmed Nafei on 18/05/2026.
//

import UIKit
import XCTest
@testable import PerformanceSuite

final class ViewControllerLeaksReceiverDefaultsTests: XCTestCase {

    private final class BareReceiver: ViewControllerLeaksReceiver {
        // Intentionally does not implement `shouldTrack(viewController:)` —
        // relies on the protocol-extension default.
        var received: [ObjectIdentifier] = []
        func viewControllerLeakReceived(viewController: UIViewController) {
            received.append(ObjectIdentifier(viewController))
        }
    }

    private final class OverridingReceiver: ViewControllerLeaksReceiver {
        let predicate: (UIViewController) -> Bool
        init(predicate: @escaping (UIViewController) -> Bool) {
            self.predicate = predicate
        }
        func viewControllerLeakReceived(viewController: UIViewController) {}
        func shouldTrack(viewController: UIViewController) -> Bool {
            predicate(viewController)
        }
    }

    private final class MarkerViewController: UIViewController {}

    func testDefaultShouldTrackReturnsTrueWhenNotImplemented() {
        let receiver = BareReceiver()

        XCTAssertTrue(receiver.shouldTrack(viewController: UIViewController()))
        XCTAssertTrue(receiver.shouldTrack(viewController: MarkerViewController()))
    }

    func testOverrideOfShouldTrackWinsOverDefaultOnConcreteType() {
        let receiver = OverridingReceiver { $0 is MarkerViewController == false }

        XCTAssertTrue(receiver.shouldTrack(viewController: UIViewController()))
        XCTAssertFalse(receiver.shouldTrack(viewController: MarkerViewController()))
    }

    func testOverrideOfShouldTrackIsDynamicallyDispatchedThroughExistential() {
        // Critical correctness test: `shouldTrack` is declared as a protocol
        // *requirement* (not extension-only) so an override on a conforming
        // type must fire even when the receiver is held as a `ViewControllerLeaksReceiver`
        // existential.
        //
        // ``ViewControllerLeaksObserver`` holds its receiver through this
        // existential type and consults `shouldTrack` before dispatching, and
        // ``MultiViewControllerLeaksReceiver`` overrides `shouldTrack` to expose
        // its chain-wide predicate. If this test failed, the chain-wide
        // predicate would silently be bypassed in production.
        let existential: ViewControllerLeaksReceiver = OverridingReceiver { _ in false }

        XCTAssertFalse(existential.shouldTrack(viewController: UIViewController()))
    }

    func testDefaultShouldTrackIsExposedThroughExistential() {
        // Conforming types that don't implement `shouldTrack` pick up the
        // extension default; the existential dispatches to it.
        let existential: ViewControllerLeaksReceiver = BareReceiver()

        XCTAssertTrue(existential.shouldTrack(viewController: UIViewController()))
    }
}
