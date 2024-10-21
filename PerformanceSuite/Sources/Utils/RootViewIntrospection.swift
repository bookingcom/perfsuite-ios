//
//  RootViewIntrospection.swift
//  PerformanceSuite
//
//  Created by Gleb Tarasov on 06/12/2021.
//

import SwiftUI
import UIKit

/// Our performance monitoring works on the `UIViewController` level.
/// If you use pure SwiftUI navigation, we still will have separate `UIHostingController` for every pushed screen,
/// but it will be hard to understand, which `View` is the root screen view for some `UIHostingController`.
/// To get the real root view of every `UIHostingController` we use this protocol.
/// We use protocol, not just `UIHostingController` extension method to avoid problems with casting `UIViewController` to a generic `UIHostingController`.
public protocol RootViewIntrospectable {
    func introspectRootView() -> Any
}

extension UIHostingController: RootViewIntrospectable {
    /// Returns the real root view of the controller. Ignores different SwiftUI wrappers like `ModifiedContent`, `AnyView` or so on.
    /// - Returns: the real root view if it is possible to find it, or the `rootView`, if introspection failed.
    public func introspectRootView() -> Any {
        return RootViewIntrospection.shared.rootView(view: rootView)
    }
}

final class RootViewIntrospection {
    static let shared = RootViewIntrospection()

    private let parser = GenericTypeParser()

    /// Looking for the first meaningful SwiftUI view in the tree. We skip all the possible containers and modifiers.
    /// - Parameter view: view hierarchy to look up in
    /// - Returns: the same view if we couldn't parse it, or the internal view which we consider the first meaningful
    func rootView(view: Any) -> Any {
        let mirror = Mirror(reflecting: view)
        if let mirrorChild = mirror.children.first(where: { possibleRootChildAttributeNames.contains($0.label) }) {
            return rootView(view: mirrorChild.value)
        } else {
            return view
        }
    }


    /// Looking for all the meaningful views in the hierarchy.
    /// Method similar to `rootView(view:)`, but it looks deeper into the hierarchy and looks not for the single child,
    /// but for all possible meaningful views.
    /// For example, it takes all the children of `VStack { ... }`, `HStack { ... }`, etc.
    /// - Parameter view: view hierarchy to look up in
    /// - Returns: all children views we consider meaningful
    func meaningfulViews(view: Any) -> [Any] {
        let mirror = Mirror(reflecting: view)
        var result: [Any] = []

        var hadChild = false
        for ch in mirror.children {
            if possibleRootChildAttributeNames.contains(ch.label)
                || possibleMeaningfulChildAttributeNames.contains(ch.label) {
                result += meaningfulViews(view: ch.value)
                hadChild = true
            }
        }

        if hadChild {
            return result
        } else if mirror.displayStyle == .optional && mirror.children.isEmpty {
            // this is an optional value with nil inside, return nothing
            return []
        } else {
            // no children found, returning view itself
            return [view]
        }
    }

    private let possibleRootChildAttributeNames: Set<String?> = [
        "some",  // is used in Optional<SomeView>
        "storage",  // is used in AnyView, Text
        "anyTextStorage", // is used in Text
        "view",  // is used in AnyViewStorage
        "content",  // is used in ModifiedContent
        "base", // is used in ModifiedElements
        "_tree", // is used in VStack/HStack
        "tree", // is used in LazyVStack/LazyHStack
        "value", // is used in TupleView
        "custom", // is used in Base
        "trueContent", // is used in `if ... else ...`
        "falseContent", // is used in `if ... else ...`
    ]

    private let possibleMeaningfulChildAttributeNames: Set<String?> = [
        ".0", ".1", ".2", ".3", ".4", ".5", ".6", ".7", ".8", ".9", // are used in view builders with multiple children
        "elements", // is used in _ViewList_View
    ]

    func description(viewController: UIViewController) -> String {
        if let introspectable = viewController as? RootViewIntrospectable {
            // For SwiftUI hosting controller we are trying to find a root view, not the controller itself.
            // This is happening only on a new screen appearance, so shouldn't affect performance a lot.
            let root = introspectable.introspectRootView()
            let meaningful = meaningfulViews(view: root)
            return meaningful
                .map { description($0) }
                .filter { !$0.isEmpty }
                .joined(separator: ", ")

        } else {
            return description(viewController)
        }
    }

    private func collapseSwiftUIGenerics(type: String) -> String {
        if let parsed = try? parser.parseType(input: type) {
            return parsed.description
        } else {
            return type
        }
    }

    private func description(_ view: Any) -> String {
        let type = String(describing: type(of: view))
        return collapseSwiftUIGenerics(type: type)
    }
}
