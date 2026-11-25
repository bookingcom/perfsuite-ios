//
//  ReceiverIdentifier.swift
//  PerformanceSuite
//

import UIKit

/// An identifier that PerformanceSuite passes to metrics receivers, stored without owning a view controller.
///
/// UIKit marks a view controller as deallocating when its last reference is released off main, but runs `dealloc`
/// later on main. If its view leaves the window in between, UIKit forms a weak reference to it and the app aborts.
/// Identifiers are kept and passed to receivers on `PerformanceMonitoring.queue` and `consumerQueue`, so a
/// `UIViewController` identifier is held weakly, an identifier can expose a view controller it references through
/// ``ViewControllerReferencing``, and receivers are called through ``withIdentifier(_:)``.
final class ReceiverIdentifier<Identifier> {

    init(_ identifier: Identifier) {
        // releaseViewControllersOnMain: on cleanup, keep the branches and drop the experiment check.
        if PerformanceMonitoring.experiments.releaseViewControllersOnMain, let viewController = identifier as? UIViewController {
            self.strongIdentifier = nil
            self.identifierViewController = viewController
        } else {
            self.strongIdentifier = identifier
        }
        if PerformanceMonitoring.experiments.releaseViewControllersOnMain {
            // releaseViewControllersOnMain: variant implementation; keep on cleanup.
            // Kept weakly, so it stays protected after a view controller identifier is gone.
            let references = retain { [(identifier as? ViewControllerReferencing)?.referencedViewController] }
            referencedViewController = references.first?.takeUnretainedValue()
            releaseOnMain(references)
        }
    }

    private let strongIdentifier: Identifier?
    private weak var identifierViewController: UIViewController?
    private weak var referencedViewController: UIViewController?

    /// The view controller the identifier describes, if it is not the identifier itself. Set once on
    /// `PerformanceMonitoring.queue` before the identifier is used.
    weak var viewController: UIViewController?

    /// Calls `body` with the identifier while none of its view controllers can be released off main.
    ///
    /// Returns `nil` without calling `body` when the identifier is a view controller that is already gone.
    @discardableResult
    func withIdentifier<Result>(_ body: (Identifier) -> Result?) -> Result? {
        var result: Result?
        retainingViewControllers {
            if let identifier = strongIdentifier ?? (identifierViewController as? Identifier) {
                result = body(identifier)
            }
        }
        return result
    }

    /// Calls `body` while none of the identifier's view controllers can be released off main, also when the identifier
    /// is gone. For receiver code that gets no identifier, like `MeasurementHandle.cancel()`.
    func retainingViewControllers(during body: () -> Void) {
        PerformanceSuite.retainingViewControllers({ viewControllers }, during: body)
    }

    /// The view controllers to keep from being released off main, loaded from weak references.
    var viewControllers: [UIViewController?] {
        let identifierViewController = identifierViewController
        let referencing = (strongIdentifier as? ViewControllerReferencing) ?? (identifierViewController as? ViewControllerReferencing)
        return [viewController, identifierViewController, referencing?.referencedViewController, referencedViewController]
    }
}

/// Runs `body` with the view controllers retained, if they are still alive, and releases those retains on main after
/// `body` returns.
///
/// Code in `body` that loads a view controller from a weak reference, like a receiver resolving its screen, gets a
/// strong temporary that could otherwise be the last reference, released off main.
func retainingViewControllers(_ viewControllers: () -> [UIViewController?], during body: () -> Void) {
    guard PerformanceMonitoring.experiments.releaseViewControllersOnMain else {
        // releaseViewControllersOnMain: base implementation; remove on cleanup.
        body()
        return
    }
    // releaseViewControllersOnMain: variant implementation; keep on cleanup.
    retainingViewControllersUntilMain(viewControllers, during: body)
}

/// ``retainingViewControllers(_:during:)`` regardless of the experiment.
func retainingViewControllersUntilMain(_ viewControllers: () -> [UIViewController?], during body: () -> Void) {
    let references = retain(viewControllers)
    // Objective-C code autoreleases what it loads from weak references. Drain those here, while retained.
    autoreleasepool {
        body()
    }
    releaseOnMain(references)
}

func retainingViewController(_ viewController: () -> UIViewController?, during body: () -> Void) {
    retainingViewControllers({ [viewController()] }, during: body)
}

/// Releases on main, right away when already on main.
func releaseOnMain(_ references: [Unmanaged<UIViewController>]) {
    guard !references.isEmpty else {
        return
    }
    if Thread.isMainThread {
        references.forEach { $0.release() }
    } else {
        DispatchQueue.main.async {
            references.forEach { $0.release() }
        }
    }
}

/// A separate function, so the strong temporaries from `viewControllers()` are gone before the retains are released.
func retain(_ viewControllers: () -> [UIViewController?]) -> [Unmanaged<UIViewController>] {
    return autoreleasepool {
        viewControllers().compactMap { viewController in
            viewController.map { Unmanaged.passRetained($0) }
        }
    }
}
