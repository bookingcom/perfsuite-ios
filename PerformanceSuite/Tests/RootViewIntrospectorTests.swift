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

    func testMyView() {
        let view = MyView()
        let rootView = introspector.rootView(view: view)
        XCTAssert(rootView is MyView)
    }

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

    func testIfViewTrue() {
        condition = true
        let controller = UIHostingController(rootView: ifView)
        let root = controller.introspectRootView()
        XCTAssert(root is MyFirstView)
    }

    func testIfViewFalse() {
        condition = false
        let controller = UIHostingController(rootView: ifView)
        let root = controller.introspectRootView()
        XCTAssert(root is MySecondView)
    }

    var condition: Bool = false

    @ViewBuilder var ifView: some View {
        if condition {
            MyFirstView()
        } else {
            MySecondView()
        }
    }

    private struct MyFirstView: View {
        var body: some View {
            Text("first")
        }
    }

    private struct MySecondView: View {
        var body: some View {
            Text("second")
        }
    }

    private struct MyView: View {
        // adding some props to make sure Mirror.children are not empty
        let prop1 = "my_prop1"
        var prop2 = 2

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
        let view =
        VStack {
            AnyView(MyView())
                .navigationViewStyle(.stack)
                .navigationTitle(Text("Test"))
                .frame(width: 200, height: 200, alignment: .center)
                .onAppear {
                    debugPrint("test")
                }
        }
        return AnyView(view)
    }

    func testDescriptionForUIViewController() {
        let controller = UIViewController()
        XCTAssertEqual("UIViewController", introspector.description(viewController: controller))

        let myController = MyViewController()
        XCTAssertEqual("MyViewController", introspector.description(viewController: myController))
    }

    func testDescriptionForText() {
        let controller = UIHostingController(rootView: Text("my text"))
        XCTAssertEqual("LocalizedTextStorage", introspector.description(viewController: controller))
    }

    func testDescriptionForTextWithModifier() {
        let controller = UIHostingController(rootView: Text("my text").onAppear { })
        XCTAssertEqual("LocalizedTextStorage", introspector.description(viewController: controller))
    }

    func testDescriptionForSimpleView() {
        let controller = UIHostingController(rootView: MyView())
        XCTAssertEqual("MyView", introspector.description(viewController: controller))
    }

    func testDescriptionForSimpleViewWithModifiers() {
        let controller = UIHostingController(rootView: MyView().onAppear { }.onDisappear { }.onTapGesture { })
        XCTAssertEqual("MyView", introspector.description(viewController: controller))
    }

    func testDescriptionForComplexView() {
        let controller = UIHostingController(rootView: makeComplexView())
        XCTAssertEqual("MyView", introspector.description(viewController: controller))
    }

    func testDescriptionForVeryComplexView() {
        let controller = UIHostingController(rootView: makeVeryComplexView())
        XCTAssertEqual("InputText, SearchDestinationList, ProgressView", introspector.description(viewController: controller))
    }

    func testDescriptionForVeryComplexViewWithConditionsTrue() {
        condition = true
        let controller = UIHostingController(rootView: makeComplexViewWithConditions())
        XCTAssertEqual("InputText", introspector.description(viewController: controller))
    }

    func testDescriptionForVeryComplexViewWithConditionsFalse() {
        condition = false
        let controller = UIHostingController(rootView: makeComplexViewWithConditions())
        XCTAssertEqual("SearchDestinationList, ProgressView", introspector.description(viewController: controller))
    }

    @ViewBuilder private func makeVeryComplexView() -> some View {
        LazyHStack {
            EmptyView()
            Button("my title", action: { })
            VStack {
                EmptyView()
                ZStack {
                    CardContainer {
                        HStack {
                            Button("Button") {
                                print("Button Tapped")
                            }
                            .padding()
                            .background(Color.blue)
                            .zIndex(1.0)

                            InputText()
                                .accessibility(identifier: "inputText")
                                .font(.callout)
                                .autocorrectionDisabled()
                        }
                    }
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(lineWidth: 2)
                            .foregroundColor(.gray)
                    )
                    .padding()
                    .padding()
                    .zIndex(1.0)

                    AnyView(SearchDestinationList())

                    VStack {
                        ProgressView()
                            .padding()
                        Spacer()
                    }
                }
                Spacer()
                EmptyView()
            }
        }
    }

    @ViewBuilder private func makeComplexViewWithConditions() -> some View {
        LazyHStack {
            EmptyView()
            Button("my title", action: { })
            VStack {
                EmptyView()
                ZStack {
                    if condition {
                        CardContainer {
                            HStack {
                                Button("Button") {
                                    print("Button Tapped")
                                }
                                .padding()
                                .background(Color.blue)
                                .zIndex(1.0)
                                if !condition {
                                    AnyView(SearchDestinationList())
                                }
                                InputText()
                                    .accessibility(identifier: "inputText")
                                    .font(.callout)
                                    .autocorrectionDisabled()
                            }
                        }
                        .overlay(
                            RoundedRectangle(cornerRadius: 16)
                                .stroke(lineWidth: 2)
                                .foregroundColor(.gray)
                        )
                        .padding()
                        .padding()
                        .zIndex(1.0)
                    } else {
                        if !condition {
                            AnyView(SearchDestinationList())
                        }

                        VStack {
                            ProgressView()
                                .padding()
                            Spacer()
                        }
                    }
                }
                Spacer()
                EmptyView()
            }
        }
    }
}

private class MyViewController: UIViewController { }


private struct InputText: View {
    @State private var text: String = ""

    var body: some View {
        TextField("Enter text", text: $text)
    }
}

private struct ProgressView: View {
    var body: some View {
        SwiftUI.ProgressView()
    }
}

private struct CardContainer<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
    }
}

private struct SearchDestinationList: View {
    var body: some View {
        Text("SearchDestinationList")
    }
}
