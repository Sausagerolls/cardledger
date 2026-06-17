import SwiftUI
import SwiftData
import UIKit

/// "Desktop access" screen: start a local web server so any browser on the same network
/// can view the inventory. Shows the address + a QR to open it.
struct ServerView: View {
    @Environment(SettingsStore.self) private var settings
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    @Query(sort: \Card.createdAt, order: .reverse) private var cards: [Card]
    @Query(sort: \GameSystem.sortIndex) private var systems: [GameSystem]

    @State private var server = LANServer.shared

    private var url: String? {
        guard server.isRunning, let ip = LANServer.wifiIPAddress() else { return nil }
        return "http://\(ip):\(server.activePort)"
    }
    private var localURL: String? {
        server.isRunning ? "http://cardledger.local:\(server.activePort)" : nil
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Theme.spacing4) {
                    header
                    toggleCard
                    if server.isRunning { addressCard }
                    infoCard
                    if let err = server.lastError { errorCard(err) }
                }
                .padding(Theme.spacing4)
            }
            .background(Theme.background)
            .navigationTitle("Desktop")
            .onAppear {
                server.editHandler = { action, request in applyEdit(action, request) }
                #if DEBUG
                if ProcessInfo.processInfo.arguments.contains("-startServer") && !server.isRunning {
                    server.start()
                }
                #endif
                pushData()
            }
            .onChange(of: snapshotKey) { _, _ in pushData() }
            .onChange(of: server.isRunning) { _, running in
                UIApplication.shared.isIdleTimerDisabled = running   // keep awake while serving
                if running { pushData() }
            }
            .onChange(of: scenePhase) { _, phase in
                // iOS suspends the app (and tears down its network) in the background, so
                // stop the server cleanly before that happens — no scary error, just off.
                if phase != .active && server.isRunning {
                    server.stop()
                    server.lastError = nil
                }
            }
            .onDisappear { /* keep server running across tabs */ }
        }
    }

    // MARK: Cards

    private var header: some View {
        VStack(spacing: Theme.spacing2) {
            Image(systemName: "wifi.router").font(.system(size: 44)).foregroundStyle(Theme.accent)
            Text("View on any computer").font(.title3.weight(.semibold))
            Text("Open the address below in a browser on a PC or Mac connected to the same Wi-Fi.")
                .font(.subheadline).foregroundStyle(Theme.textSecondary).multilineTextAlignment(.center)
        }
        .padding(.top, Theme.spacing3)
    }

    private var toggleCard: some View {
        SurfaceCard {
            Toggle(isOn: Binding(
                get: { server.isRunning },
                set: { $0 ? server.start() : server.stop() }
            )) {
                VStack(alignment: .leading) {
                    Text(server.isRunning ? "Server on" : "Server off").font(.headline)
                    Text(server.isRunning ? "Browsers on this network can connect" : "Turn on to share to your computer")
                        .font(.caption).foregroundStyle(Theme.textSecondary)
                }
            }
            .tint(Theme.profit)
        }
    }

    private var addressCard: some View {
        SurfaceCard {
            VStack(spacing: Theme.spacing3) {
                if let url, let qr = QRCodeGenerator.image(fromString: url) {
                    qr.resizable().interpolation(.none).frame(width: 150, height: 150)
                    Text("Scan to open, or type it in your browser:")
                        .font(.caption).foregroundStyle(Theme.textSecondary)
                }
                if let url { addressRow(url) }
                if let localURL { addressRow(localURL) }
            }
            .frame(maxWidth: .infinity)
        }
    }

    private func addressRow(_ value: String) -> some View {
        HStack {
            Text(value).font(.mono).textSelection(.enabled)
            Spacer()
            Button { UIPasteboard.general.string = value } label: { Image(systemName: "doc.on.doc") }
        }
    }

    private var infoCard: some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: Theme.spacing2) {
                Label("Keep this app open", systemImage: "info.circle").font(.headline)
                Text("iOS pauses apps in the background, so the page is available only while CardLedger is open on this device. The screen is kept awake while the server is on.")
                    .font(.caption).foregroundStyle(Theme.textSecondary)
                Text("Anyone on the same Wi-Fi can browse, add and edit your cards from the page — only share the address with people you trust.")
                    .font(.caption).foregroundStyle(Theme.textSecondary)
            }
        }
    }

    private func errorCard(_ text: String) -> some View {
        SurfaceCard {
            Label(text, systemImage: "exclamationmark.triangle").foregroundStyle(Theme.loss).font(.subheadline)
        }
    }

    // MARK: Data push

    /// A cheap string that changes whenever anything servable changes, so we re-push.
    private var snapshotKey: String {
        let cardsPart = cards.map { "\($0.shortCode)|\($0.name)|\($0.purchasePriceMinor)|\($0.isSold)|\($0.quantity)|\($0.photos?.count ?? 0)" }.joined(separator: ";")
        return cardsPart + "#\(settings.currencyCode)\(settings.vatPercent)\(settings.defaultProfitPercent)\(settings.taxMethod.rawValue)"
    }

    private func pushData() {
        let df = DateFormatter(); df.dateStyle = .medium
        let iso = DateFormatter(); iso.dateFormat = "yyyy-MM-dd"; iso.timeZone = .current

        let webCards = cards.map { c in
            WebCard(
                shortCode: c.shortCode,
                name: c.name,
                game: c.gameSystem?.name ?? "",
                gameCode: c.gameSystem?.code ?? "",
                setName: c.setName,
                number: c.cardNumber,
                rarity: c.rarity,
                condition: c.condition.label,
                conditionRaw: c.condition.rawValue,
                quantity: c.quantity,
                purchasePrice: NSDecimalNumber(decimal: c.purchasePrice).doubleValue,
                purchaseDate: df.string(from: c.purchaseDate),
                purchaseISO: iso.string(from: c.purchaseDate),
                isSold: c.isSold,
                salePrice: NSDecimalNumber(decimal: c.salePrice).doubleValue,
                soldDate: c.soldDate.map { df.string(from: $0) },
                notes: c.notes,
                photoCount: c.sortedPhotos.count
            )
        }
        let webSettings = WebSettings(
            currency: settings.currencyCode,
            vatPercent: settings.vatPercent,
            defaultProfitPercent: settings.defaultProfitPercent,
            method: settings.taxMethod.rawValue
        )
        let games = systems.map { WebGame(name: $0.name, code: $0.code) }
        let payload = WebPayload(settings: webSettings, cards: webCards, games: games)
        let data = (try? JSONEncoder().encode(payload)) ?? Data("{}".utf8)

        var photos: [String: [Data]] = [:]
        for c in cards { photos[c.shortCode] = c.sortedPhotos.map(\.imageData) }

        let csv = CSVExporter.csvString(for: cards, currencyCode: settings.currencyCode)
        let pdf = (try? QRSheetExporter.makePDF(for: cards)).flatMap { try? Data(contentsOf: $0) } ?? Data()
        server.updateData(payload: data, csv: csv, pdf: pdf, photos: photos)
    }

    // MARK: Browser edits (runs on the main thread; only uses `context`)

    private func applyEdit(_ action: String, _ r: EditRequest) -> EditResult {
        switch action {
        case "delete":
            guard let code = r.shortCode, let card = CardLookup.find(code: code, in: context) else {
                return EditResult(ok: false, message: "Card not found", shortCode: nil)
            }
            context.delete(card)
            try? context.save()
            return EditResult(ok: true, message: "Deleted", shortCode: code)

        case "create":
            let gameCode = (r.gameCode ?? "").uppercased()
            var d = FetchDescriptor<GameSystem>(predicate: #Predicate { $0.code == gameCode })
            d.fetchLimit = 1
            guard let system = (try? context.fetch(d))?.first else {
                return EditResult(ok: false, message: "Unknown game system", shortCode: nil)
            }
            let code = ShortCodeGenerator.makeUnique(prefix: system.code, in: context)
            let card = Card(shortCode: code, name: r.name ?? "", gameSystem: system,
                            purchasePriceMinor: Self.minor(r.purchasePrice),
                            purchaseDate: Self.date(r.purchaseDate) ?? Date(),
                            quantity: r.quantity ?? 1)
            applyFields(to: card, r)
            context.insert(card)
            try? context.save()
            return EditResult(ok: true, message: "Added", shortCode: code)

        case "update":
            guard let code = r.shortCode, let card = CardLookup.find(code: code, in: context) else {
                return EditResult(ok: false, message: "Card not found", shortCode: nil)
            }
            applyFields(to: card, r)
            try? context.save()
            return EditResult(ok: true, message: "Saved", shortCode: code)

        default:
            return EditResult(ok: false, message: "Unknown action", shortCode: nil)
        }
    }

    private func applyFields(to card: Card, _ r: EditRequest) {
        if let v = r.name { card.name = v }
        if let v = r.setName { card.setName = v }
        if let v = r.number { card.cardNumber = v }
        if let v = r.rarity { card.rarity = v }
        if let v = r.condition, let c = CardCondition(rawValue: v) { card.condition = c }
        if let v = r.quantity { card.quantity = max(v, 1) }
        if let v = r.purchasePrice { card.purchasePriceMinor = Self.minor(v) }
        if let v = r.purchaseDate, let d = Self.date(v) { card.purchaseDate = d }
        if let v = r.notes { card.notes = v }
        if let v = r.isSold {
            card.isSold = v
            if v, card.soldDate == nil { card.soldDate = Date() }
        }
        if let v = r.salePrice { card.salePriceMinor = Self.minor(v) }
    }

    private static func minor(_ value: Double?) -> Int { Int(((value ?? 0) * 100).rounded()) }
    private static func date(_ string: String?) -> Date? {
        guard let string else { return nil }
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; f.timeZone = .current
        return f.date(from: string)
    }
}

// MARK: - Web payload DTOs

private struct WebPayload: Encodable {
    let settings: WebSettings
    let cards: [WebCard]
    let games: [WebGame]
}
private struct WebGame: Encodable {
    let name: String
    let code: String
}
private struct WebSettings: Encodable {
    let currency: String
    let vatPercent: Double
    let defaultProfitPercent: Double
    let method: String
}
private struct WebCard: Encodable {
    let shortCode: String
    let name: String
    let game: String
    let gameCode: String
    let setName: String
    let number: String
    let rarity: String
    let condition: String
    let conditionRaw: String
    let quantity: Int
    let purchasePrice: Double
    let purchaseDate: String
    let purchaseISO: String
    let isSold: Bool
    let salePrice: Double
    let soldDate: String?
    let notes: String
    let photoCount: Int
}
