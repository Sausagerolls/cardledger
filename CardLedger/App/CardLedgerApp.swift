import SwiftUI
import SwiftData

@main
struct CardLedgerApp: App {
    let container: ModelContainer
    @State private var settings = SettingsStore()

    init() {
        let container = PersistenceController.makeContainer()
        self.container = container
        PersistenceController.seedIfNeeded(container.mainContext)
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-seedSample") {
            PersistenceController.seedSampleCards(container.mainContext)
        }
        #endif
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(settings)
                .tint(Theme.accent)
        }
        .modelContainer(container)
    }
}
