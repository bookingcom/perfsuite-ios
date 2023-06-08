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

    func rootView(view: Any) -> Any {
        let mirror = Mirror(reflecting: view)
        if let mirrorChild = mirror.children.first(where: { possibleMirrorChildAttributeNames.contains($0.label) }) {
            return rootView(view: mirrorChild.value)
        } else {
            return view
        }
    }

    private let possibleMirrorChildAttributeNames: Set<String?> = [
        "some",  // is used in Optional<SomeView>
        "storage",  // is used in AnyView
        "view",  // is used in AnyViewStorage
        "content",  // is used in ModifiedContent
    ]
}
