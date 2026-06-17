import SwiftUI
import SwiftData

/// Top-level navigation. A tab bar keeps iPhone and iPad familiar; each tab is its own
/// navigation stack. A deep link (`cardledger://card/<code>`) opens the matching card.
struct RootView: View {
    @Environment(\.modelContext) private var context
    @State private var selectedTab: Tab = {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-startServer") { return .desktop }
        #endif
        return .inventory
    }()
    @State private var deepLinkedCard: Card?

    enum Tab { case inventory, scan, desktop, settings }

    var body: some View {
        TabView(selection: $selectedTab) {
            InventoryView()
                .tabItem { Label("Inventory", systemImage: "square.grid.2x2") }
                .tag(Tab.inventory)

            ScanView()
                .tabItem { Label("Scan", systemImage: "qrcode.viewfinder") }
                .tag(Tab.scan)

            ServerView()
                .tabItem { Label("Desktop", systemImage: "wifi.router") }
                .tag(Tab.desktop)

            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape") }
                .tag(Tab.settings)
        }
        .onOpenURL { url in handleDeepLink(url) }
        .sheet(item: $deepLinkedCard) { card in
            NavigationStack { CardDetailView(card: card) }
        }
        .onAppear {
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("-openFirstCard") {
                var d = FetchDescriptor<Card>(sortBy: [SortDescriptor(\.createdAt)])
                d.fetchLimit = 1
                deepLinkedCard = try? context.fetch(d).first
            }
            #endif
        }
    }

    private func handleDeepLink(_ url: URL) {
        guard url.scheme == "cardledger", url.host == "card" else { return }
        let code = url.lastPathComponent
        if let card = CardLookup.find(code: code, in: context) {
            deepLinkedCard = card
        }
    }
}

/// Shared helper to resolve a card by its short code.
enum CardLookup {
    static func find(code: String, in context: ModelContext) -> Card? {
        let target = code.uppercased()
        var descriptor = FetchDescriptor<Card>(predicate: #Predicate { $0.shortCode == target })
        descriptor.fetchLimit = 1
        return (try? context.fetch(descriptor))?.first
    }
}
