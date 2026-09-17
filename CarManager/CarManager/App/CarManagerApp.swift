import SwiftUI

@main
struct CarManagerApp: App {
    @State private var model: AppModel

    init() {
        // The object graph is composed exactly once, here.
        _model = State(initialValue: AppModel(dependencies: .live()))
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .appModel(model)
                .environment(model.router)
                // Deep links and notification taps take the SAME path: parse → guard → navigate.
                .onOpenURL { url in model.router.handle(url: url) }
                .task { await model.bootstrap() }
        }
    }
}
