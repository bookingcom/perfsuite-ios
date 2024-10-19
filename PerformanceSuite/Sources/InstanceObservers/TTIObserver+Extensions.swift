//
//  TTIObserver+Extensions.swift
//  PerformanceSuite
//
//  Created by Gleb Tarasov on 08/12/2021.
//

import SwiftUI
import UIKit

public extension UIViewController {

    /// Call this method in `UIViewController` that you want to be tracked for TTI.
    ///
    /// You should call this method when your screen is usable by the user: all needed data is loaded and displayed.
    /// Good place can be when your network request is finished and you reloaded your view with the loaded data.
    /// Or it can be called in `cellForRowAtIndexPath:` when some of main cells is displayed.
    /// Only first call of this method is considered. Other subsequent calls are ignored.
    ///
    /// ```
    /// class YourViewController: UIViewController {
    ///     override func viewDidLoad() {
    ///          super.viewDidLoad()
    ///          networkManager.loadData { [self] response in
    ///              self.reloadData(response)
    ///              self.screenIsReady()
    ///          }
    ///     }
    /// }
    /// ```
    @objc func screenIsReady() {
        let observer = ViewControllerObserverFactoryHelper.existingObserver(forChild: self, identifier: TTIObserverHelper.identifier) as? ScreenIsReadyProvider
        observer?.screenIsReady()
    }


    /// This method is used to start TTI and TTFR from the different place, not `UIViewController.init` method.

    /// The first case is when TTI should be started before view controller is created.
    /// For example, if you start network request on the previous screen and show loading indicator there.
    /// And create controller only after network request succeeded.
    /// Don't forget to call `screenCreationCancelled` when network request failed in this case.
    ///
    /// The second case is when TTI should be started after view controller is created.
    /// For example, when you create UIViewController and cache it in some property earlier then showing it.
    /// Then you call this method before actually showing this controller.
    @objc static func screenIsBeingCreated() {
        TTIObserverHelper.startCustomCreationTime()
    }


    /// Call this method in case you called `screenIsBeingCreated`, but screen won't be created.
    /// For example network request failed, or user tapped `cancel` or so on.
    @objc static func screenCreationCancelled() {
        TTIObserverHelper.clearCustomCreationTime()
    }
}

extension View {


    /// Call this method on some SwiftUI view, which appearance shows that the screen is ready for the user.
    ///
    /// You should call this method when your screen is usable by the user: all needed data is loaded and displayed.
    /// Good place can be when your network request is finished and you showed the first cell or some other meaningful view.
    /// Only first call of this method is considered. Other subsequent calls are ignored until this screen disappears.
    /// - Parameter condition: you can pass condition block which determines if we should call `screenIsReady` or not. Default value is `true`.
    ///
    ///
    /// ```
    /// var body: some View {
    ///     if viewModel.isLoading {
    ///         ProgressView()
    ///     } else {
    ///         Text("Screen is ready").screenIsReadyOnAppear()
    ///     }
    /// }
    /// ```
    @ViewBuilder public func screenIsReadyOnAppear(_ condition: @autoclosure @escaping () -> Bool = true) -> some View {
        overlay(overlayView(condition: condition, onAppear: { $0.screenIsReady() }))
    }

    @ViewBuilder private func overlayView(condition: () -> Bool, onAppear: @escaping (UIViewController) -> Void) -> some View {
        if condition() {
            ControllerIntrospectionView(onAppear: onAppear).frame(width: 0, height: 0)
        } else {
            EmptyView()
        }
    }
}
