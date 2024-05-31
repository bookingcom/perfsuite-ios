//
//  ControllerIntrospectionViewTests.swift
//  PerformanceSuite-Tests
//
//  Created by Gleb Tarasov on 08/12/2021.
//

import SwiftUI
import XCTest

@testable import PerformanceSuite

private struct MyView: View {
    init(callback: @escaping (UIViewController) -> Void) {
        self.callback = callback
    }
    private let callback: (UIViewController) -> Void

    var body: some View {
        return Text("BlaBla").overlay(ControllerIntrospectionView(onAppear: callback))
    }
}

class ControllerIntrospectionViewTests: XCTestCase {

    func testControllerIntrospection() throws {
        let exp = expectation(description: "view controller")

        let view = MyView { vc in
            XCTAssert(vc is RootViewIntrospectable)
            if let rootView = (vc as? RootViewIntrospectable)?.introspectRootView() {
                XCTAssert(rootView is MyView)
                exp.fulfill()
            }
        }

        let vc = UIHostingController(rootView: view)

        let window = makeWindow()
        window.rootViewController = vc
        window.makeKeyAndVisible()

        waitForExpectations(timeout: 2, handler: nil)
    }
}
