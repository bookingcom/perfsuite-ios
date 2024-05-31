//
//  MenuView.swift
//  PerformanceApp
//
//  Created by Gleb Tarasov on 18/12/2023.
//

import SwiftUI

struct MenuView: View {
    var body: some View {
        List {
            Section(header: Text("Issues")) {
                Text("Non-fatal hang").onTapGesture {
                    IssuesSimulator.simulateNonFatalHang()
                }

                Text("Fatal hang").onTapGesture {
                    IssuesSimulator.simulateFatalHang()
                }

                Text("Watchdog termination").onTapGesture {
                    IssuesSimulator.simulateWatchdogTermination()
                }

                Text("Crash").onTapGesture {
                    IssuesSimulator.simulateCrash()
                }

                NavigationLink(destination: MemoryLeakView()) {
                    Text("Memory Leak")
                }
            }

            Section(header: Text("Performance metrics")) {
                let ttiMode = ListMode("1", delayInterval: 1, popOnAppear: true)
                NavigationLink(destination: ListView(mode: ttiMode)) {
                    Text("TTI")
                }

                NavigationLink(destination: FragmentTTIView()) {
                    Text("Fragment TTI")
                }

                let renderingMode = ListMode("2", cellSleep: 0.1, delayInterval: 1, scrollOnAppear: true, popOnAppear: true)
                NavigationLink(destination: ListView(mode: renderingMode)) {
                    Text("Freeze Time")
                }
            }
        }
    }
}

extension MenuView: PerformanceTrackable {
    var performanceScreen: PerformanceScreen? {
        return .menu
    }
}
