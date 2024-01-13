//
//  FragmentTTIView.swift
//  AppHost-PerformanceSuite-Unit-Tests
//
//  Created by Gleb Tarasov on 13/01/2024.
//

import PerformanceSuite
import SwiftUI

class FragmentTTIGenerator {
    static func generate(presentationMode: Binding<PresentationMode>) {
        /// fragment1: 100 + 50 + 100 + 50 = 300ms
        /// fragment2: 50ms
        /// fragment3: 100ms
        let fragment1 = PerformanceMonitoring.startFragmentTTI(identifier: "fragment1")
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(100)) {
            let fragment2 = PerformanceMonitoring.startFragmentTTI(identifier: "fragment2")
            DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(50)) {
                fragment2.fragmentIsReady()
                let fragment3 = PerformanceMonitoring.startFragmentTTI(identifier: "fragment3")
                DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(100)) {
                    fragment3.fragmentIsReady()
                    DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(50)) {
                        fragment1.fragmentIsReady()
                        presentationMode.wrappedValue.dismiss()
                    }
                }
            }
        }
    }
}

struct FragmentTTIView: View {
    @Environment(\.presentationMode) var presentationMode

    var body: some View {
        Text("Fragment TTI showcase").onAppear {
            FragmentTTIGenerator.generate(presentationMode: presentationMode)
        }
    }
}
