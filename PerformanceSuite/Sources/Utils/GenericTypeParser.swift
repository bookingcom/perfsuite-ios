//
//  GenericTypeParser.swift
//  PerformanceSuite
//
//  Created by Gleb Tarasov on 25/09/2023.
//

import Foundation

/// List of types we should skip in the description,
/// but include all the children.
private let skipName: Set<String> = [
    "LazyHStack",
    "LazyVStack",
    "VStack",
    "HStack",
    "ZStack",
    "TupleView",
    "Block",
    "Tuple",
    "UnaryElements",
    "TypedUnaryViewGenerator",
    "ListContainer",
    "ForEach",
    "Array",
]

/// List of types we should skip in the description,
/// but include the first child.
private let takeFirst: Set<String> = [
    "ModifiedContent",
    "Optional",
    "Row",
    "IDView",
    "AnyPublisher",
    "GeometryReader",
]

/// List of types we should skip in the description completely.
private let skipAll: Set<String> = [
    "Button",
    "Text",
    "String",
    "Bool",
    "Int",
    "Double",
    "Range",
    "Never",
    "Spacer",
    "Divider",
    "EmptyView",
    "Color",
    "Font",
    "SubscriptionView",
]

/// Generic type structure
struct TypeElement {
    var name: String
    var children: [TypeElement]

    private enum SkipMode {
        case skipAll
        case skipName
        case takeFirstChild
        case none
    }

    private var skipMode: SkipMode {
        if skipAll.contains(name) {
            return .skipAll
        }

        if takeFirst.contains(name) {
            return .takeFirstChild
        }

        if skipName.contains(name) {
            return .skipName
        }

        if name.hasPrefix("_") {
            return .skipName
        }

        if name.hasSuffix("Modifier") {
            return .takeFirstChild
        }

        if name.hasSuffix("TraitKey") {
            return .skipAll
        }

        return .none
    }

    var description: String {
        let takeName: Bool
        let childrenToTake: [TypeElement]
        switch skipMode {
        case .skipAll:
            takeName = false
            childrenToTake = []
        case .skipName:
            takeName = false
            childrenToTake = children
        case .takeFirstChild:
            takeName = false
            childrenToTake = Array(children.prefix(1))
        case .none:
            takeName = true
            childrenToTake = children
        }

        let childrenDescriptions = childrenToTake.map { $0.description }.filter { !$0.isEmpty}
        if takeName {
            if childrenDescriptions.isEmpty {
                return name
            } else {
                return name + "<" + childrenDescriptions.joined(separator: ", ") + ">"
            }
        } else {
            if childrenDescriptions.isEmpty {
                return ""
            } else {
                return childrenDescriptions.joined(separator: ", ")
            }
        }
    }
}

private enum Bracket: CaseIterable {
    case angled
    case regular

    var openSymbol: Character {
        switch self {
        case .angled:
            return "<"
        case .regular:
            return "("
        }
    }

    var closeSymbol: Character {
        switch self {
        case .angled:
            return ">"
        case .regular:
            return ")"
        }
    }
}

private let blockReturnTypeString = " -> "
private let blockReturnTypeSymbol = "}"
private let tupleTypeName = "Tuple"
private let blockTypeName = "Block"


private enum ParsingError: Error {
    case emptyName
    case noOpeningBracketFound
    case noClosingBracketFound
    case closingBeforeOpening
    case unbalancedSimpleBrackets
    case unbalancedBrackets
    case regularBracketNotFirst
    case wrongReturnTypeString
    case noOpeningRegularBracketFound
    case noClosingRegularBracketFound
}

/// Class to parse generic SwiftUI types representation,
/// we use it to generate more readable descriptions.
///
/// For example such type:
/// LazyHStack<VStack<TupleView<(ZStack<TupleView<(ModifiedContent<ModifiedContent<ModifiedContent<ModifiedContent<CardContainer<
/// HStack<TupleView<(ModifiedContent<ModifiedContent<ModifiedContent<Button<Text>, _PaddingLayout>, _BackgroundModifier<Color>>,
/// _TraitWritingModifier<ZIndexTraitKey>>, ModifiedContent<ModifiedContent<ModifiedContent<InputText, AccessibilityAttachmentModifier>,
/// _EnvironmentKeyWritingModifier<Optional<Font>>>, _EnvironmentKeyWritingModifier<Optional<Bool>>>)>>>, _OverlayModifier<ModifiedContent
/// <_StrokedShape<RoundedRectangle>, _EnvironmentKeyWritingModifier<Optional<Color>>>>>, _PaddingLayout>, _PaddingLayout>,
/// _TraitWritingModifier<ZIndexTraitKey>>, SearchDestinationList, VStack<TupleView<(ModifiedContent<ProgressView<EmptyView, EmptyView>,
/// _PaddingLayout>, Spacer)>>)>>, Spacer)>>>
///
/// can be collapsed into this, by dropping all SwiftUI views and modifiers:
/// CardContainer<InputText>, SearchDestinationList, ProgressView
///
class GenericTypeParser {

    /// Parses the string representation of a generic type like `MyView<MyChild1, MyChild2>`
    /// into the structure TypeElement.
    func parseType(input: String) throws -> TypeElement {
        let preparedInput = String(input.replacingOccurrences(of: blockReturnTypeString, with: blockReturnTypeSymbol))
        return try parseTypeInternal(input: preparedInput)
    }


    private func parseTypeInternal(input: String) throws -> TypeElement {
        guard let regularStartIndex = input.firstIndex(of: Bracket.regular.openSymbol) else {
            return try parseClass(input: input)
        }

        guard let angledStartIndex = input.firstIndex(of: Bracket.angled.openSymbol) else {
            return try parseTupleOrBlock(input: input)
        }

        if regularStartIndex < angledStartIndex {
            // if regular bracket is earlier, than angled, it means this is either block (a, b) -> c, or tuple (a, b, c)
            return try parseTupleOrBlock(input: input)
        } else {
            return try parseClass(input: input)
        }
    }

    private func parseClass(input: String) throws -> TypeElement {
        let startIndex = input.firstIndex(of: Bracket.angled.openSymbol)
        let endIndex = input.lastIndex(of: Bracket.angled.closeSymbol)

        guard let startIndex = startIndex else {
            if endIndex != nil {
                throw ParsingError.noOpeningBracketFound
            }

            return TypeElement(name: input, children: [])
        }

        guard let endIndex = endIndex else {
            throw ParsingError.noClosingBracketFound
        }

        let name = String(input[..<startIndex])
        if name.isEmpty {
            throw ParsingError.emptyName
        }
        let children = try parseChildren(startIndex: startIndex, endIndex: endIndex, input: input)
        return TypeElement(name: name, children: children)
    }

    private func parseTupleOrBlock(input: String) throws -> TypeElement {
        guard let startIndex = input.firstIndex(of: Bracket.regular.openSymbol) else {
            throw ParsingError.noOpeningRegularBracketFound
        }
        guard let endIndex = input.lastIndex(of: Bracket.regular.closeSymbol) else {
            throw ParsingError.noClosingRegularBracketFound
        }

        let indexAfterEnd = input.index(after: endIndex)

        if startIndex != input.startIndex {
            throw ParsingError.regularBracketNotFirst
        }

        if indexAfterEnd == input.endIndex {
            // this is a tuple
            let children = try parseChildren(startIndex: startIndex, endIndex: endIndex, input: input)
            return TypeElement(name: tupleTypeName, children: children)
        }

        let blockArguments = try parseChildren(startIndex: startIndex, endIndex: endIndex, input: input)

        let remainingString = input[indexAfterEnd...]
        if !remainingString.hasPrefix(blockReturnTypeSymbol) {
            throw ParsingError.wrongReturnTypeString
        }

        let resultTypeString = String(remainingString.dropFirst(blockReturnTypeSymbol.count))
        let blockResult = try parseTypeInternal(input: resultTypeString)

        return TypeElement(name: blockTypeName, children: blockArguments + [blockResult])
    }

    private func parseChildren(startIndex: String.Index, endIndex: String.Index, input: String) throws -> [TypeElement] {
        let indexAfterStart = input.index(after: startIndex)
        if endIndex < indexAfterStart {
            throw ParsingError.closingBeforeOpening
        } else if endIndex == indexAfterStart {
            return []
        }

        let childrenStr = String(input[indexAfterStart..<endIndex])
        let childrenStrs = try splitByComma(input: childrenStr)
        var children: [TypeElement] = []
        for ch in childrenStrs {
            children.append(try parseTypeInternal(input: ch))
        }
        return children
    }

    // Split by comma, but taking brackets into consideration.
    // We split only by commas which are on the root level of brackets
    private func splitByComma(input: String) throws -> [String] {
        let input = input.trimmingCharacters(in: .whitespaces)
        var results: [String] = []
        var currentStr = ""

        func appendResult() {
            if !currentStr.isEmpty {
                results.append(currentStr.trimmingCharacters(in: .whitespaces))
            }
        }

        var bracketsStack: [Bracket] = []

        for ch in input {
            if ch == "," && bracketsStack.isEmpty {
                appendResult()
                currentStr = ""
                continue
            }

            for b in Bracket.allCases {
                switch ch {
                case b.openSymbol:
                    bracketsStack.append(b)
                case b.closeSymbol:
                    if b != bracketsStack.last {
                        throw ParsingError.unbalancedBrackets
                    }
                    bracketsStack.removeLast()
                default:
                    break
                }
            }

            currentStr.append(ch)
        }
        appendResult()
        return results
    }
}
