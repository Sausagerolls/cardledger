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
        if ProcessInfo.processInfo.arguments.contains("-dumpQRPDF") {
            PersistenceController.seedSampleCards(container.mainContext)
            if let cards = try? container.mainContext.fetch(FetchDescriptor<Card>()),
               let url = try? QRSheetExporter.makePDF(for: cards) {
                let dest = URL.documentsDirectory.appendingPathComponent("qr.pdf")
                try? FileManager.default.removeItem(at: dest)
                try? FileManager.default.copyItem(at: url, to: dest)
            }
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
