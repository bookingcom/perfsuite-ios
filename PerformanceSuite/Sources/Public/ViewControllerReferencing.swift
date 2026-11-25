//
//  ViewControllerReferencing.swift
//  PerformanceSuite
//

import UIKit

/// Adopt in a screen or fragment identifier that references a view controller.
///
/// Identifiers are kept and passed to receivers off main, so they must reference view controllers only weakly. A receiver
/// that loads such a weak reference gets a strong temporary that could be the last reference, releasing the view controller
/// off main. With `Experiments.releaseViewControllersOnMain`, PerformanceSuite keeps `referencedViewController` alive while
/// receivers use the identifier and releases it on main. A screen's own view controller is covered without this protocol.
public protocol ViewControllerReferencing {
    /// The referenced view controller, loaded from a weak reference.
    var referencedViewController: UIViewController? { get }
}
