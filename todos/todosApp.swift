import SwiftUI

@main
struct todosApp: App {
    @State private var store = TaskStore()
    @AppStorage("appearance") private var appearance = AppAppearance.system.rawValue

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(store)
                .preferredColorScheme((AppAppearance(rawValue: appearance) ?? .system).colorScheme)
                .task { RewardFeedback.shared.prepare() }
        }
    }
}
