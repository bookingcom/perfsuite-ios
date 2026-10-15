//
//  FragmentRenderingView.swift
//  PerformanceApp
//

import PerformanceSuite
import SwiftUI

class FragmentRenderingGenerator {
    static func generate(presentationMode: Binding<PresentationMode>) {
        let fragment = PerformanceMonitoring.startFragmentRendering(identifier: "fragment1")
        // Let the display link start ticking before blocking the main thread
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(100)) {
            Thread.sleep(forTimeInterval: 0.5)
            DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(100)) {
                fragment.fragmentRenderingFinished()
                presentationMode.wrappedValue.dismiss()
            }
        }
    }
}

struct FragmentRenderingView: View {
    @Environment(\.presentationMode) var presentationMode

    var body: some View {
        Text("Fragment Rendering showcase").onAppear {
            FragmentRenderingGenerator.generate(presentationMode: presentationMode)
        }
    }
}
