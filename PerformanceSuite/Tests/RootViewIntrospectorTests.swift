//
//  RootViewIntrospectionTests.swift
//  PerformanceSuite-Tests
//
//  Created by Gleb Tarasov on 07/12/2021.
//

import SwiftUI
import XCTest

@testable import PerformanceSuite

@available(iOS 14.0, *)
class RootViewIntrospectionTests: XCTestCase {

    private let introspector = RootViewIntrospection()

    func testAnyView() {
        let view = AnyView(MyView())
        let rootView = introspector.rootView(view: view)
        XCTAssert(rootView is MyView)
    }

    func testOptionalAnyView() {
        let view: AnyView? = AnyView(MyView())
        let rootView = introspector.rootView(view: view as Any)
        XCTAssert(rootView is MyView)
    }

    func testModifiedView() {
        let view = MyView()
            .navigationViewStyle(.stack)
            .navigationTitle(Text("Test"))
        let rootView = introspector.rootView(view: view)
        XCTAssert(rootView is MyView)
    }

    func testComplexView() {
        let view = makeComplexView()
        let rootView = introspector.rootView(view: view)
        XCTAssert(rootView is MyView)
    }

    func testHostingController() {
        let view = makeComplexView()
        let controller = UIHostingController(rootView: view)
        let root = introspector.rootView(view: controller.rootView)
        XCTAssert(root is MyView)
    }

    func testHostingControllerWithOptionalView() {
        let view: AnyView? = makeComplexView()
        let controller = UIHostingController(rootView: view)
        let root = controller.introspectRootView()
        XCTAssert(root is MyView)
    }

    // uncomment to run performance test on SwiftUI introspection
    func disabled_testPerformance() {
        let view = makeComplexView()
        let controller = UIHostingController(rootView: view)

        self.measure {
            for _ in 0..<1000 {
                _ = controller.introspectRootView()
            }
        }
    }

    private struct MyView: View {
        var body: some View {
            Text("blablabla")
                .frame(width: 10, height: 20, alignment: .center)
                .background(Color.red)
                .padding()
                .onAppear {
                    debugPrint("test")
                }
        }
    }

    private func makeComplexView() -> AnyView {
        let view = AnyView(MyView())
            .navigationViewStyle(.stack)
            .navigationTitle(Text("Test"))
            .frame(width: 200, height: 200, alignment: .center)
            .onAppear {
                debugPrint("test")
            }
        return AnyView(view)
    }
}
