//
//  RenderingUseCasesView.swift
//  PerformanceApp
//
//  Created by Gleb Tarasov on 18/12/2023.
//

import SwiftUI

private struct Item: Identifiable, Hashable {
    static func == (lhs: Item, rhs: Item) -> Bool {
        return lhs.title == rhs.title
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(title)
    }

    let title: String
    let controllerType: UIViewController.Type

    var id: String {
        return title
    }
}


/// Different slow patterns to test how rendering metrics react to the different use cases.
struct RenderingUseCasesView: View {
    var body: some View {
        List {
            Section(header: Text("List")) {
                listItems
            }

            Section(header: Text("Modal list")) {
                modalListItems
            }
        }
        .sheet(
            isPresented: Binding(
                get: {
                    return presentedScreen != nil
                },
                set: { _ in
                }),
            onDismiss: { self.presentedScreen = nil },
            content: {
                self.presentedScreen ?? AnyView(EmptyView())
            })
    }

    @ViewBuilder private var listItems: some View {
        ForEach(ListMode.allCases, id: \.self) { mode in
            NavigationLink(destination: ListView(mode: mode)) {
                Text(mode.title)
            }
        }
    }

    @ViewBuilder private var modalListItems: some View {
        ForEach(ListMode.allCases, id: \.self) { mode in
            Text(mode.title).onTapGesture {
                self.presentedScreen = AnyView(ListView(mode: mode))
            }
        }
    }

    @State var presentedScreen: AnyView?
}

extension RenderingUseCasesView: PerformanceTrackable {
    var performanceScreen: PerformanceScreen? {
        return .rendering
    }
}


struct RenderingUseCasesView_Previews: PreviewProvider {
    static var previews: some View {
        RenderingUseCasesView()
    }
}
