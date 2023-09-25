//
//  GenericTypeParserTests.swift
//  PerformanceSuite-Tests
//
//  Created by Gleb Tarasov on 25/09/2023.
//

@testable import PerformanceSuite
import XCTest

final class GenericTypeParserTests: XCTestCase {

    func testSimple() throws {
        let parser = GenericTypeParser()

        var parsed = try parser.parseType(description: "MyView")
        XCTAssertEqual(parsed.name, "MyView")
        XCTAssertEqual(parsed.children.count, 0)
        XCTAssertEqual(parsed.description, "MyView")

        parsed = try parser.parseType(description: "MyView<ChildView>")
        XCTAssertEqual(parsed.name, "MyView")
        XCTAssertEqual(parsed.children.count, 1)
        XCTAssertEqual(parsed.children.first?.name, "ChildView")
        XCTAssertEqual(parsed.children.first?.children.count, 0)
        XCTAssertEqual(parsed.description, "MyView<ChildView>")

        parsed = try parser.parseType(description: "MyView<ChildView1, ChildView2>")
        XCTAssertEqual(parsed.name, "MyView")
        XCTAssertEqual(parsed.children.count, 2)
        XCTAssertEqual(parsed.children.first?.name, "ChildView1")
        XCTAssertEqual(parsed.children.first?.children.count, 0)
        XCTAssertEqual(parsed.children.last?.name, "ChildView2")
        XCTAssertEqual(parsed.children.last?.children.count, 0)
        XCTAssertEqual(parsed.description, "MyView<ChildView1, ChildView2>")

        parsed = try parser.parseType(description: "MyView<ChildView1<ChildChildView11, ChildChildView12>, ChildView2>")
        XCTAssertEqual(parsed.name, "MyView")
        XCTAssertEqual(parsed.children.count, 2)
        XCTAssertEqual(parsed.children.first?.name, "ChildView1")
        XCTAssertEqual(parsed.children.first?.children.count, 2)
        XCTAssertEqual(parsed.children.last?.name, "ChildView2")
        XCTAssertEqual(parsed.children.last?.children.count, 0)
        XCTAssertEqual(parsed.description, "MyView<ChildView1<ChildChildView11, ChildChildView12>, ChildView2>")
    }

    func testWithSimpleBrackets() throws {
        let parser = GenericTypeParser()

        var parsed = try parser.parseType(description: "MyView<(MyChild1, MyChild2, MyChild3)>")
        XCTAssertEqual(parsed.name, "MyView")
        XCTAssertEqual(parsed.children.count, 3)

        XCTAssertEqual(parsed.children.first?.name, "MyChild1")
        XCTAssertEqual(parsed.children.first?.children.count, 0)
        XCTAssertEqual(parsed.children.last?.name, "MyChild3")
        XCTAssertEqual(parsed.children.last?.children.count, 0)
        XCTAssertEqual(parsed.description, "MyView<MyChild1, MyChild2, MyChild3>")


        parsed = try parser.parseType(description: "MyView<(MyChild1<MyChild2<MyChild3, MyChild4>, MyChild5>, MyChild6)>")
        XCTAssertEqual(parsed.name, "MyView")
        XCTAssertEqual(parsed.children.count, 2)

        XCTAssertEqual(parsed.children.first?.name, "MyChild1")
        XCTAssertEqual(parsed.children.first?.children.count, 2)
        XCTAssertEqual(parsed.children.last?.name, "MyChild6")
        XCTAssertEqual(parsed.children.last?.children.count, 0)
        XCTAssertEqual(parsed.description, "MyView<MyChild1<MyChild2<MyChild3, MyChild4>, MyChild5>, MyChild6>")
    }

    func testSkippingSwiftUITypes() throws {
        let parser = GenericTypeParser()

        var parsed = try parser.parseType(description: "ModifiedContent<ProgressView<EmptyView, EmptyView>, _PaddingLayout>, Spacer")
        XCTAssertEqual(parsed.description, "ProgressView")

        parsed = try parser.parseType(description: "ZStack<TupleView<(ModifiedContent<ModifiedContent<ModifiedContent<ModifiedContent<CardContainer<HStack<EmptyView, EmptyView>>>>>>)>>")
        XCTAssertEqual(parsed.description, "CardContainer")

        parsed = try parser.parseType(description: """
LazyHStack<VStack<TupleView<(ZStack<TupleView<(ModifiedContent<ModifiedContent<ModifiedContent<ModifiedContent<CardContainer<HStack<TupleView<(ModifiedContent<ModifiedContent<ModifiedContent<Button<Text>, _PaddingLayout>, _BackgroundModifier<Color>>, _TraitWritingModifier<ZIndexTraitKey>>, ModifiedContent<ModifiedContent<ModifiedContent<InputText, AccessibilityAttachmentModifier>, _EnvironmentKeyWritingModifier<Optional<Font>>>, _EnvironmentKeyWritingModifier<Optional<Bool>>>)>>>, _OverlayModifier<ModifiedContent<_StrokedShape<RoundedRectangle>, _EnvironmentKeyWritingModifier<Optional<Color>>>>>, _PaddingLayout>, _PaddingLayout>, _TraitWritingModifier<ZIndexTraitKey>>, SearchDestinationList, VStack<TupleView<(ModifiedContent<ProgressView<EmptyView, EmptyView>, _PaddingLayout>, Spacer)>>)>>, Spacer)>>>
""")

        XCTAssertEqual(parsed.description, "CardContainer<InputText>, SearchDestinationList, ProgressView")
    }

    func testParsingErrors() throws {
        let parser = GenericTypeParser()

        XCTAssertThrowsError(try parser.parseType(description: "My<"))
        XCTAssertThrowsError(try parser.parseType(description: "<My"))
        XCTAssertThrowsError(try parser.parseType(description: "<My>"))
        XCTAssertThrowsError(try parser.parseType(description: "<My><My>"))
        XCTAssertThrowsError(try parser.parseType(description: "><"))
        XCTAssertThrowsError(try parser.parseType(description: ">My<"))
        XCTAssertThrowsError(try parser.parseType(description: "TestView<MyView"))
        XCTAssertThrowsError(try parser.parseType(description: "TestViewMyView>"))
        XCTAssertThrowsError(try parser.parseType(description: "TestView<<MyView>"))
        XCTAssertThrowsError(try parser.parseType(description: "TestView<(MyView)"))
        XCTAssertThrowsError(try parser.parseType(description: "TestView<(MyView>"))
        XCTAssertThrowsError(try parser.parseType(description: "ModifiedContent<ProgressView<EmptyView, EmptyView>, _PaddingLayout, Spacer"))
    }
}
