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
        }
    }
}

extension MenuView: PerformanceTrackable {
    var performanceScreen: PerformanceScreen? {
        return .menu
    }
}
