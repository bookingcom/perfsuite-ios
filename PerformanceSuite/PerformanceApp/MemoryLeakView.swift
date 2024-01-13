//
//  MemoryLeakView.swift
//  PerformanceApp
//
//  Created by Gleb Tarasov on 16/02/2022.
//

import SwiftUI

struct MemoryLeakView: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> MemoryLeakViewController {
        return MemoryLeakViewController()
    }

    func updateUIViewController(_ uiViewController: MemoryLeakViewController, context: Context) {}
}

class MemoryLeakViewController: UIViewController {
    private let ref = Ref()

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        // create retain cycle
        ref.viewController = self

        DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(1)) {
            self.navigationController?.popViewController(animated: true)
        }
    }
}

private class Ref {
    var viewController: UIViewController?
}
