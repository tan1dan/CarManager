import SwiftUI

private struct AppModelKey: EnvironmentKey {
    // nonisolated: a nil default needs no isolation, and isolating the key would push the
    // whole conformance onto the main actor.
    static let defaultValue: AppModel? = nil
}

public extension EnvironmentValues {
    /// Views read this ONLY to construct child ViewModels via factories — never to call
    /// a repository or a service directly.
    var appModel: AppModel? {
        get { self[AppModelKey.self] }
        set { self[AppModelKey.self] = newValue }
    }
}

public extension View {
    func appModel(_ model: AppModel) -> some View {
        environment(\.appModel, model)
    }
}
