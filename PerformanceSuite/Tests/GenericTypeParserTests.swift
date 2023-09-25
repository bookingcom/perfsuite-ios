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

        var parsed = try parser.parseType(input: "MyView")
        XCTAssertEqual(parsed.name, "MyView")
        XCTAssertEqual(parsed.children.count, 0)
        XCTAssertEqual(parsed.description, "MyView")

        parsed = try parser.parseType(input: "MyView<ChildView>")
        XCTAssertEqual(parsed.name, "MyView")
        XCTAssertEqual(parsed.children.count, 1)
        XCTAssertEqual(parsed.children.first?.name, "ChildView")
        XCTAssertEqual(parsed.children.first?.children.count, 0)
        XCTAssertEqual(parsed.description, "MyView<ChildView>")

        parsed = try parser.parseType(input: "MyView<ChildView1, ChildView2>")
        XCTAssertEqual(parsed.name, "MyView")
        XCTAssertEqual(parsed.children.count, 2)
        XCTAssertEqual(parsed.children.first?.name, "ChildView1")
        XCTAssertEqual(parsed.children.first?.children.count, 0)
        XCTAssertEqual(parsed.children.last?.name, "ChildView2")
        XCTAssertEqual(parsed.children.last?.children.count, 0)
        XCTAssertEqual(parsed.description, "MyView<ChildView1, ChildView2>")

        parsed = try parser.parseType(input: "MyView<ChildView1<ChildChildView11, ChildChildView12>, ChildView2>")
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

        var parsed = try parser.parseType(input: "MyView<(MyChild1, MyChild2, MyChild3)>")
        XCTAssertEqual(parsed.name, "MyView")
        XCTAssertEqual(parsed.children.count, 1)
        XCTAssertEqual(parsed.children.first?.name, "Tuple")
        XCTAssertEqual(parsed.children.first?.children.count, 3)

        XCTAssertEqual(parsed.children.first?.children.first?.name, "MyChild1")
        XCTAssertEqual(parsed.children.first?.children.first?.children.count, 0)

        XCTAssertEqual(parsed.children.first?.children.last?.name, "MyChild3")
        XCTAssertEqual(parsed.children.first?.children.last?.children.count, 0)

        XCTAssertEqual(parsed.description, "MyView<MyChild1, MyChild2, MyChild3>")


        parsed = try parser.parseType(input: "MyView<(MyChild1<MyChild2<MyChild3, MyChild4>, MyChild5>, MyChild6)>")
        XCTAssertEqual(parsed.name, "MyView")
        XCTAssertEqual(parsed.children.count, 1)
        XCTAssertEqual(parsed.description, "MyView<MyChild1<MyChild2<MyChild3, MyChild4>, MyChild5>, MyChild6>")
    }

    func testBlocksAndTuples() throws {
        let parser = GenericTypeParser()

        var parsed = try parser.parseType(input: "() -> MyType")
        XCTAssertEqual(parsed.name, "Block")
        XCTAssertEqual(parsed.children.count, 1)
        XCTAssertEqual(parsed.children.first?.name, "MyType")

        parsed = try parser.parseType(input: "(MyType)")
        XCTAssertEqual(parsed.name, "Tuple")
        XCTAssertEqual(parsed.children.count, 1)
        XCTAssertEqual(parsed.children.first?.name, "MyType")

        parsed = try parser.parseType(input: "MyType1<() -> MyType2>")
        XCTAssertEqual(parsed.name, "MyType1")
        XCTAssertEqual(parsed.children.count, 1)
        XCTAssertEqual(parsed.children.first?.name, "Block")
        XCTAssertEqual(parsed.children.first?.children.count, 1)

        XCTAssertEqual(parsed.children.first?.children.first?.name, "MyType2")
        XCTAssertEqual(parsed.children.first?.children.first?.children.count, 0)



        parsed = try parser.parseType(input: "MyModifier<Optional<() -> MyType>>")
        XCTAssertEqual(parsed.name, "MyModifier")
        XCTAssertEqual(parsed.children.count, 1)
        XCTAssertEqual(parsed.children.first?.name, "Optional")
        XCTAssertEqual(parsed.children.first?.children.count, 1)
        XCTAssertEqual(parsed.description, "MyType")

        parsed = try parser.parseType(input: "MyModifier<Optional<(MyType1) -> MyType2>>")
        XCTAssertEqual(parsed.description, "MyType1, MyType2")

        parsed = try parser.parseType(input: "MyModifier<Optional<(MyType1, MyType2, MyType3) -> MyType4<MyType5>>>")
        XCTAssertEqual(parsed.description, "MyType1, MyType2, MyType3, MyType4<MyType5>")
    }

    func testSkippingSwiftUITypes() throws {
        let parser = GenericTypeParser()

        var parsed = try parser.parseType(input: "ModifiedContent<ProgressView<EmptyView, EmptyView>, _PaddingLayout>, Spacer")
        XCTAssertEqual(parsed.description, "ProgressView")

        parsed = try parser.parseType(input: "ZStack<TupleView<(ModifiedContent<ModifiedContent<ModifiedContent<ModifiedContent<CardContainer<HStack<EmptyView, EmptyView>>>>>>)>>")
        XCTAssertEqual(parsed.description, "CardContainer")

        parsed = try parser.parseType(input: """
LazyHStack<VStack<TupleView<(ZStack<TupleView<(ModifiedContent<ModifiedContent<ModifiedContent<ModifiedContent<CardContainer<HStack<TupleView<(ModifiedContent<ModifiedContent<ModifiedContent<Button<Text>, _PaddingLayout>, _BackgroundModifier<Color>>, _TraitWritingModifier<ZIndexTraitKey>>, ModifiedContent<ModifiedContent<ModifiedContent<InputText, AccessibilityAttachmentModifier>, _EnvironmentKeyWritingModifier<Optional<Font>>>, _EnvironmentKeyWritingModifier<Optional<Bool>>>)>>>, _OverlayModifier<ModifiedContent<_StrokedShape<RoundedRectangle>, _EnvironmentKeyWritingModifier<Optional<Color>>>>>, _PaddingLayout>, _PaddingLayout>, _TraitWritingModifier<ZIndexTraitKey>>, SearchDestinationList, VStack<TupleView<(ModifiedContent<ProgressView<EmptyView, EmptyView>, _PaddingLayout>, Spacer)>>)>>, Spacer)>>>
""")
        XCTAssertEqual(parsed.description, "CardContainer<InputText>, SearchDestinationList, ProgressView")

        parsed = try parser.parseType(input: """
UnaryElements<TypedUnaryViewGenerator<VStack<TupleView<(ModifiedContent<ModifiedContent<ModifiedContent<CardContainer<ModifiedContent<ModifiedContent<ModifiedContent<_HStack<TupleView<(ModifiedContent<ModifiedContent<ModifiedContent<Button, PaddingModifier>, BackgroundModifier>, _TraitWritingModifier<ZIndexTraitKey>>, ModifiedContent<ModifiedContent<ModifiedContent<ModifiedContent<ModifiedContent<InputText, AccessibilityAttachmentModifier>, _EnvironmentKeyWritingModifier<UIReturnKeyType>>, _EnvironmentKeyWritingModifier<Optional<() -> ResponderFocusStrategy>>>, _EnvironmentKeyWritingModifier<UITextAutocorrectionType>>, _EnvironmentKeyWritingModifier<Bool>>)>>, _FlexFrameLayout>, _PaddingLayout>, _OverlayModifier<ModifiedContent<_ShapeView<_StrokedShape<_Inset>, ForegroundStyle>, _EnvironmentKeyWritingModifier<Optional<Color>>>>>, EmptyView>, PaddingModifier>, PaddingModifier>, _TraitWritingModifier<ZIndexTraitKey>>, ZStack<TupleView<(SearchDestinationList, Optional<VStack<TupleView<(ModifiedContent<ProgressView, PaddingModifier>, Spacer)>>>)>>, Spacer)>>>>
""")
        XCTAssertEqual(parsed.description, "CardContainer<InputText>, SearchDestinationList, ProgressView")
    }

    func testParsingErrors() throws {
        let parser = GenericTypeParser()

        XCTAssertThrowsError(try parser.parseType(input: "My<"))
        XCTAssertThrowsError(try parser.parseType(input: "<My"))
        XCTAssertThrowsError(try parser.parseType(input: "<My>"))
        XCTAssertThrowsError(try parser.parseType(input: "<My><My>"))
        XCTAssertThrowsError(try parser.parseType(input: "><"))
        XCTAssertThrowsError(try parser.parseType(input: ">My<"))
        XCTAssertThrowsError(try parser.parseType(input: "TestView<MyView"))
        XCTAssertThrowsError(try parser.parseType(input: "TestViewMyView>"))
        XCTAssertThrowsError(try parser.parseType(input: "TestView<<MyView>"))
        XCTAssertThrowsError(try parser.parseType(input: "TestView<(MyView)"))
        XCTAssertThrowsError(try parser.parseType(input: "TestView<(MyView>"))
        XCTAssertThrowsError(try parser.parseType(input: "ModifiedContent<ProgressView<EmptyView, EmptyView>, _PaddingLayout, Spacer"))
    }
}
