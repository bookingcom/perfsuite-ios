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
]

/// List of types we should skip in the description,
/// but include the first child.
private let takeFirst: Set<String> = [
    "ModifiedContent",
    "Optional",
]

/// List of types we should skip in the description completely.
private let skipAll: Set<String> = [
    "Button",
    "Text",
    "Spacer",
    "EmptyView",
    "Color",
    "Font",
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

private enum ParsingError: Error {
    case emptyName
    case noClosingBracketFound
    case noOpeningBracketFound
    case closingBeforeOpening
    case unbalancedSimpleBrackets
    case unbalancedBrackets
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
    func parseType(description: String) throws -> TypeElement {
        let startIndex = description.firstIndex(of: Bracket.angled.openSymbol)
        let endIndex = description.lastIndex(of: Bracket.angled.closeSymbol)

        guard let startIndex = startIndex else {
            if endIndex != nil {
                throw ParsingError.noOpeningBracketFound
            }

            return TypeElement(name: description, children: [])
        }

        guard let endIndex = endIndex else {
            throw ParsingError.noClosingBracketFound
        }
        let afterStartIndex = description.index(after: startIndex)
        if endIndex <= afterStartIndex {
            throw ParsingError.closingBeforeOpening
        }

        let name = String(description[..<startIndex])
        if name.isEmpty {
            throw ParsingError.emptyName
        }
        let childrenStr = String(description[afterStartIndex..<endIndex])
        let childrenStrs = try splitByComma(input: childrenStr)
        var children: [TypeElement] = []
        for ch in childrenStrs {
            children.append(try parseType(description: ch))
        }

        return TypeElement(name: name, children: children)
    }

    // Split by comma, but taking brackets into consideration.
    // We split only by commas which are on the root level of brackets
    private func splitByComma(input: String) throws -> [String] {
        let input =  try dropWrappingBrackets(input: input.trimmingCharacters(in: .whitespaces))
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

    private func dropWrappingBrackets(input: String) throws -> String {
        if input.first == Bracket.regular.openSymbol && input.last == Bracket.regular.closeSymbol {
            // Remove the brackets if both of them present
            let startIndex = input.index(after: input.startIndex)
            let endIndex = input.index(before: input.endIndex)
            return String(input[startIndex..<endIndex])
        } else if input.first == Bracket.regular.openSymbol || input.last == Bracket.regular.closeSymbol {
            // Only one of the brackets is present
            throw ParsingError.unbalancedSimpleBrackets
        } else {
            // No brackets, return the original string
            return input
        }
    }
}
