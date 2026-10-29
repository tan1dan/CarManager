import SwiftUI

@main
struct CarManagerApp: App {
    @State private var model: AppModel
    @State private var changes = PersistenceChangeObserver()
    @Environment(\.scenePhase) private var scenePhase

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
                .task {
                    await model.bootstrap()
                    changes.start { [model] in await model.vehicles.refresh() }
                    #if DEBUG
                    // `-openURL carmanager://…` opens a screen directly, without the system
                    // "Open in CarManager?" prompt that `simctl openurl` triggers.
                    let arguments = ProcessInfo.processInfo.arguments
                    if let index = arguments.firstIndex(of: "-openURL"), index + 1 < arguments.count,
                       let url = URL(string: arguments[index + 1]) {
                        model.router.handle(url: url)
                    }
                    #endif
                }
                // Coming back to the app may follow edits made on another device, or a
                // subscription that renewed, lapsed or was refunded while it was closed.
                .onChange(of: scenePhase) { _, phase in
                    guard phase == .active else { return }
                    Task { await model.vehicles.refresh() }
                    Task { await model.entitlements.refresh() }
                }
        }
    }
}
