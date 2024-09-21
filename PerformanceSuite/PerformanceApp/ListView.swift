//
//  ContentView.swift
//  PerformanceApp
//
//  Created by Gleb Tarasov on 30/11/2021.
//

import Combine
import SwiftUI

struct ListMode: Hashable {
    let title: String
    let cellSleep: TimeInterval
    let initSleep: TimeInterval
    let appendSleep: TimeInterval
    let delayInterval: TimeInterval
    let laggyLoadingAnimation: Bool
    let scrollOnAppear: Bool
    let popOnAppear: Bool

    init(
        _ title: String,
        cellSleep: TimeInterval = 0,
        initSleep: TimeInterval = 0,
        appendSleep: TimeInterval = 0,
        delayInterval: TimeInterval = 0,
        laggyLoadingAnimation: Bool = false,
        scrollOnAppear: Bool = false,
        popOnAppear: Bool = false
    ) {
        self.title = title
        self.cellSleep = cellSleep
        self.initSleep = initSleep
        self.appendSleep = appendSleep
        self.delayInterval = delayInterval
        self.laggyLoadingAnimation = laggyLoadingAnimation
        self.scrollOnAppear = scrollOnAppear
        self.popOnAppear = popOnAppear
    }

    static var allCases: [ListMode] {
        return [
            .none,
            .cellSleep14ms,
            .cellSleep20ms,
            .cellSleep50ms,
            .cellSleep60ms,
            .initSleep500ms,
            .initSleep3000ms,
            .appendSleep100ms,
            .appendSleep150ms,
            .delay3s,
            .delay5s,
            .delay5sCellSleep20ms,
            .delay5sCellSleep50ms,
            .laggyDelay3s,
            .laggyDelay5s,
            .laggyDelay5sCellSleep20ms,
            .laggyDelay5sCellSleep50ms,
        ]
    }

    static let none: ListMode = .init("None")
    static let cellSleep14ms: ListMode = .init("Sleep 14ms in every cell", cellSleep: 0.014)
    static let cellSleep20ms: ListMode = .init("Sleep 20ms in every cell", cellSleep: 0.020)
    static let cellSleep50ms: ListMode = .init("Sleep 50ms in every cell", cellSleep: 0.050)
    static let cellSleep60ms: ListMode = .init("Sleep 60ms in every cell", cellSleep: 0.060)
    static let initSleep500ms: ListMode = .init("Sleep 500ms on init", initSleep: 0.500)
    static let initSleep3000ms: ListMode = .init("Sleep 3000ms on init", initSleep: 3.000)
    static let appendSleep100ms: ListMode = .init("Sleep 100ms on every next page", appendSleep: 0.100)
    static let appendSleep150ms: ListMode = .init("Sleep 150ms on every next page", appendSleep: 0.150)
    static let delay3s: ListMode = .init("Delay 3s before screen is ready", delayInterval: 3.000)
    static let delay5s: ListMode = .init("Delay 5s before screen is ready", delayInterval: 5.000)
    static let delay5sCellSleep20ms: ListMode = .init(
        "Delay 5s before screen is ready, sleep 20ms in every cell", cellSleep: 0.020, delayInterval: 5.000)
    static let delay5sCellSleep50ms: ListMode = .init(
        "Delay 5s before screen is ready, sleep 50ms in every cell", cellSleep: 0.050, delayInterval: 5.000)
    static let laggyDelay3s: ListMode = .init("Laggy delay 3s before screen is ready", delayInterval: 3.000, laggyLoadingAnimation: true)
    static let laggyDelay5s: ListMode = .init("Laggy delay 5s before screen is ready", delayInterval: 5.000, laggyLoadingAnimation: true)
    static let laggyDelay5sCellSleep20ms: ListMode = .init(
        "Laggy delay 5s before screen is ready, sleep 20ms in every cell", cellSleep: 0.020, delayInterval: 5.000,
        laggyLoadingAnimation: true)
    static let laggyDelay5sCellSleep50ms: ListMode = .init(
        "Laggy delay 5s before screen is ready, sleep 50ms in every cell", cellSleep: 0.050, delayInterval: 5.000,
        laggyLoadingAnimation: true)
}

class ListViewModel: ObservableObject {
    init(mode: ListMode) {
        self.mode = mode
        if mode.delayInterval == 0 {
            isLoading = false
        }
    }
    let mode: ListMode
    var numberOfItems = 100

    func onAppear(presentationMode: Binding<PresentationMode>) {
        Thread.sleep(forTimeInterval: mode.initSleep)
        DispatchQueue.main.asyncAfter(deadline: .now() + TimeInterval(mode.delayInterval)) {
            self.isLoading = false
            if self.mode.popOnAppear {
                DispatchQueue.main.asyncAfter(deadline: .now() + TimeInterval(self.mode.delayInterval)) {
                    presentationMode.wrappedValue.dismiss()
                }
            }
        }
    }

    func onDisappear() {
        if mode.delayInterval != 0 {
            isLoading = true
        }
        self.numberOfItems = 100
    }

    func nextPage() {
        Thread.sleep(forTimeInterval: mode.appendSleep)
        self.numberOfItems += 100
    }

    @Published var isLoading: Bool = true
}

struct ListView: View {

    init(mode: ListMode) {
        self.viewModel = ListViewModel(mode: mode)
    }
    @ObservedObject private var viewModel: ListViewModel

    @Environment(\.presentationMode) var presentationMode

    var body: some View {
        content
            .onAppear {
                viewModel.onAppear(presentationMode: presentationMode)
            }
            .onDisappear {
                viewModel.onDisappear()
            }
    }

    @ViewBuilder var content: some View {
        if viewModel.isLoading {
            LaggyProgressView(laggy: self.viewModel.mode.laggyLoadingAnimation)
                .frame(alignment: .center)
        } else {
            ScrollViewReader { proxy in
                List {
                    ForEach(0..<viewModel.numberOfItems, id: \.self) { index in
                        Cell(mode: viewModel.mode).id(index)
                    }
                    .screenIsReadyOnAppear()

                    if #available(iOS 14.0, *) {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .frame(alignment: .center)
                            .onAppear {
                                DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(1)) {
                                    self.viewModel.nextPage()
                                }
                            }
                    }
                }.onAppear {
                    if viewModel.mode.scrollOnAppear {
                        DispatchQueue.main.async {
                            withAnimation {
                                proxy.scrollTo(viewModel.numberOfItems - 1, anchor: .top)
                            }
                        }

                    }
                }
            }
        }
    }
}

struct ListView_Previews: PreviewProvider {
    static var previews: some View {
        ListView(mode: .none)
    }
}


private struct Cell: View {
    init(mode: ListMode) {
        self.mode = mode
    }
    private let mode: ListMode

    var body: some View {
        Thread.sleep(forTimeInterval: mode.cellSleep)
        return VStack {
            Text("Title")
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("Subtitle")
                .frame(maxWidth: .infinity, alignment: .trailing)
            HStack {
                Text("Some")
                Spacer()
                Text("Horizontal")
                Text("Info")
                Spacer()
            }
            .frame(maxWidth: .infinity)
        }.frame(maxWidth: .infinity)
    }
}

/// Progress view that can generate dropped frames during animation if `laggy` is set to `true`
struct LaggyProgressView: View {
    init(laggy: Bool) {
        self.laggy = laggy
    }

    private let timer: Publishers.Autoconnect<Timer.TimerPublisher> = Timer.publish(every: 0.001, on: .main, in: .common).autoconnect()

    private let laggy: Bool

    @State private var progress: Int = 0

    var body: some View {
        let count = laggy ? 300 : 1
        ZStack {
            ForEach(0..<count, id: \.self) { index in
                let ratio = Double(index) / Double(count)
                Rectangle()
                    .background(gradient)
                    .frame(width: 30, height: 1000)
                    .opacity(1 - ratio)
                    .rotationEffect(Angle(degrees: 360 * Double(progress) / 100))

            }
        }
        .onReceive(timer) { _ in
            progress += 1
        }
    }

    var gradient: LinearGradient {
        let colors: [Color] = [.white, .green, .blue, .red]
        let repeatCount = progress % 600
        let repeatingColors: [Color] = Array(repeating: colors, count: repeatCount).flatMap { $0 }
        return LinearGradient(gradient: Gradient(colors: repeatingColors), startPoint: .top, endPoint: .bottom)
    }
}

extension ListView: PerformanceTrackable {
    var performanceScreen: PerformanceScreen? {
        return .list
    }
}
