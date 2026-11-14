import SwiftUI
import QueryShareCore

@main struct QueryShareApp: App {
    @State private var model = ShareModel()
    @Environment(\.scenePhase) private var scene
    var body: some Scene {
        WindowGroup {
            RootView(model: model)
                .onChange(of: scene) { _, phase in model.sceneChanged(phase) }
        }
    }
}
