//
//  HostingControllerWithAppeared.swift
//  Pods
//
//  Created by Gleb Tarasov on 21/09/2024.
//
import SwiftUI

final class HostingControllerWithAppeared<T: View>: UIHostingController<T> {

    var viewAppeared: () -> Void = {}

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        DispatchQueue.main.async {
            self.viewAppeared()
        }
    }
}
