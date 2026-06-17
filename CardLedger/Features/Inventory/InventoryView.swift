import SwiftUI
import SwiftData

struct InventoryView: View {
    @Environment(\.modelContext) private var context
    @Environment(SettingsStore.self) private var settings

    @Query(sort: \Card.createdAt, order: .reverse) private var cards: [Card]
    @Query(sort: \GameSystem.sortIndex) private var systems: [GameSystem]

    @State private var searchText = ""
    @State private var selectedSystem: GameSystem?
    @State private var statusFilter: StatusFilter = .all
    @State private var showAddCard = false
    @State private var exportFile: ExportFile?
    @State private var exportError: String?

    enum StatusFilter: String, CaseIterable { case all = "All", inStock = "In stock", sold = "Sold" }

    private let columns = [GridItem(.adaptive(minimum: 160), spacing: Theme.spacing3)]

    private var filtered: [Card] {
        cards.filter { card in
            let matchesSystem = selectedSystem == nil || card.gameSystem?.persistentModelID == selectedSystem?.persistentModelID
            let q = searchText.trimmingCharacters(in: .whitespaces).lowercased()
            let matchesSearch = q.isEmpty
                || card.name.lowercased().contains(q)
                || card.shortCode.lowercased().contains(q)        // unique instance code
                || card.cardNumber.lowercased().contains(q)       // printed code on the card
                || card.setName.lowercased().contains(q)
            let matchesStatus: Bool
            switch statusFilter {
            case .all: matchesStatus = true
            case .inStock: matchesStatus = !card.isSold
            case .sold: matchesStatus = card.isSold
            }
            return matchesSystem && matchesSearch && matchesStatus
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if cards.isEmpty {
                    EmptyStateView(
                        icon: "rectangle.stack.badge.plus",
                        title: "No cards yet",
                        message: "Tap + to log your first card with photos and a purchase price."
                    )
                } else {
                    ScrollView {
                        Picker("Status", selection: $statusFilter) {
                            ForEach(StatusFilter.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                        }
                        .pickerStyle(.segmented)
                        .padding(.horizontal, Theme.spacing4)
                        .padding(.top, Theme.spacing2)
                        systemFilterBar
                        if filtered.isEmpty {
                            EmptyStateView(icon: "magnifyingglass", title: "No matches",
                                           message: "Nothing matches your search or filter.")
                                .padding(.top, Theme.spacing6)
                        } else {
                            LazyVGrid(columns: columns, spacing: Theme.spacing3) {
                                ForEach(filtered) { card in
                                    NavigationLink {
                                        CardDetailView(card: card)
                                    } label: {
                                        CardTile(card: card).environment(settings)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.horizontal, Theme.spacing4)
                            .padding(.bottom, Theme.spacing6)
                        }
                    }
                }
            }
            .background(Theme.background)
            .navigationTitle("Inventory")
            .searchable(text: $searchText, prompt: "Search name or short code")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        Section("Spreadsheet (CSV)") {
                            Button {
                                exportCSV(filteredOnly: false)
                            } label: { Label("All cards (\(cards.count))", systemImage: "tablecells") }
                            if filtered.count != cards.count {
                                Button {
                                    exportCSV(filteredOnly: true)
                                } label: { Label("Shown (\(filtered.count))", systemImage: "line.3.horizontal.decrease") }
                            }
                        }
                        Section("QR codes for printing (PDF, 12/page)") {
                            Button {
                                exportQRSheet(filteredOnly: false)
                            } label: { Label("All cards (\(cards.count))", systemImage: "qrcode") }
                            if filtered.count != cards.count {
                                Button {
                                    exportQRSheet(filteredOnly: true)
                                } label: { Label("Shown (\(filtered.count))", systemImage: "qrcode") }
                            }
                        }
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .disabled(cards.isEmpty)
                    .accessibilityLabel("Export inventory")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showAddCard = true } label: { Image(systemName: "plus") }
                        .accessibilityLabel("Add card")
                }
            }
            .sheet(isPresented: $showAddCard) {
                AddCardView().environment(settings)
            }
            .sheet(item: $exportFile) { file in
                ShareSheet(items: [file.url])
            }
            .alert("Export failed", isPresented: .constant(exportError != nil)) {
                Button("OK") { exportError = nil }
            } message: { Text(exportError ?? "") }
        }
    }

    private func exportCSV(filteredOnly: Bool) {
        let rows = filteredOnly ? filtered : cards
        do {
            let url = try CSVExporter.writeTempFile(for: rows, currencyCode: settings.currencyCode)
            exportFile = ExportFile(url: url)
        } catch {
            exportError = error.localizedDescription
        }
    }

    private func exportQRSheet(filteredOnly: Bool) {
        let rows = filteredOnly ? filtered : cards
        do {
            let url = try QRSheetExporter.makePDF(for: rows)
            exportFile = ExportFile(url: url)
        } catch {
            exportError = error.localizedDescription
        }
    }

    private var systemFilterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Theme.spacing2) {
                filterPill(title: "All", system: nil)
                ForEach(systems) { system in
                    if (system.cards?.isEmpty == false) {
                        filterPill(title: system.code, system: system)
                    }
                }
            }
            .padding(.horizontal, Theme.spacing4)
            .padding(.vertical, Theme.spacing2)
        }
    }

    private func filterPill(title: String, system: GameSystem?) -> some View {
        let isSelected = selectedSystem?.persistentModelID == system?.persistentModelID
        return Button {
            withAnimation(.snappy) { selectedSystem = system }
        } label: {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 14).padding(.vertical, 8)
                .background(isSelected ? Theme.accent : Theme.surface, in: Capsule())
                .foregroundStyle(isSelected ? .white : Theme.textPrimary)
        }
        .buttonStyle(.plain)
    }
}

/// Grid tile: photo (or placeholder), name, short code, purchase price.
struct CardTile: View {
    @Environment(SettingsStore.self) private var settings
    let card: Card

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack {
                Rectangle().fill(Theme.surfaceRaised)
                if let data = card.sortedPhotos.first?.imageData, let ui = UIImage(data: data) {
                    Image(uiImage: ui).resizable().scaledToFill()
                } else {
                    Image(systemName: card.gameSystem?.iconSymbol ?? "rectangle.stack")
                        .font(.system(size: 40)).foregroundStyle(Theme.accent.opacity(0.4))
                }
            }
            .frame(height: 150)
            .clipped()

            VStack(alignment: .leading, spacing: 4) {
                Text(card.name.isEmpty ? "Untitled card" : card.name)
                    .font(.cardTitle).lineLimit(1)
                if !card.cardNumber.isEmpty {
                    Text(card.cardNumber).font(.caption2).foregroundStyle(Theme.textSecondary).lineLimit(1)
                }
                Text(card.shortCode).font(.mono).foregroundStyle(Theme.accent)  // unique code (the QR)
                HStack {
                    Text(settings.money(card.purchasePrice))
                        .font(.subheadline.weight(.bold)).foregroundStyle(Theme.gold)
                    Spacer()
                    if card.isSold {
                        StatChip(title: "Sold", tint: Theme.profit)
                    }
                }
            }
            .padding(Theme.spacing3)
        }
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.radiusMedium, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.radiusMedium).stroke(Theme.separator.opacity(0.5), lineWidth: 0.5))
        .clipShape(RoundedRectangle(cornerRadius: Theme.radiusMedium, style: .continuous))
    }
}
