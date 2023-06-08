//
//  ControllerIntrospectionView.swift
//  PerformanceSuite
//
//  Created by Gleb Tarasov on 08/12/2021.
//

import SwiftUI

struct ControllerIntrospectionView: UIViewRepresentable {

    let onAppear: (UIViewController) -> Void

    func makeUIView(context: Self.Context) -> ControllerIntrospectionUIView {
        return ControllerIntrospectionUIView(onAppear: onAppear)
    }

    func updateUIView(_ uiView: Self.UIViewType, context: Self.Context) {}
}

final class ControllerIntrospectionUIView: UIView {
    init(onAppear: @escaping (UIViewController) -> Void) {
        self.onAppear = onAppear
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()

        if callbackCalled {
            return
        }

        if let controller = findContainerController() {
            onAppear(controller)
            callbackCalled = true
        }
    }

    private func findContainerController() -> UIViewController? {
        var responder: UIResponder = self
        while true {
            if let nextResponder = responder.next {
                if let viewController = nextResponder as? UIViewController {
                    return viewController
                }
                responder = nextResponder
            } else {
                return nil
            }
        }
    }

    private let onAppear: (UIViewController) -> Void
    private var callbackCalled = false
}
