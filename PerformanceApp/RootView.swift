//
//  RootView.swift
//  PerformanceApp
//
//  Created by Gleb Tarasov on 01/12/2021.
//

import SwiftUI

class RootController: UIHostingController<RootView> {
    init() {
        super.init(rootView: RootView())
        Thread.sleep(forTimeInterval: 2)
        self.title = "Performance App"
    }

    @MainActor @objc required dynamic init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

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

struct RootView: View {

    var body: some View {
        List {
            Section(header: Text("List")) {
                listItems
            }

            Section(header: Text("Modal list")) {
                modalListItems
            }

            Section(header: Text("Memory leaks")) {
                memoryLeakItems
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

    @ViewBuilder private var memoryLeakItems: some View {
        NavigationLink(destination: MemoryLeakView()) {
            Text("View controller memory leak")
        }
    }

    @State var presentedScreen: AnyView?
}

struct RootView_Previews: PreviewProvider {
    static var previews: some View {
        RootView()
    }
}
