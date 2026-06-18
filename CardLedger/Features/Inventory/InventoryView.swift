import SwiftUI
import SwiftData

struct InventoryView: View {
    @Environment(\.modelContext) private var context
    @Environment(SettingsStore.self) private var settings

    @Query(sort: \Card.createdAt, order: .reverse) private var cards: [Card]
    @Query(sort: \GameSystem.sortIndex) private var systems: [GameSystem]

    @State private var searchText = ""
    @State private var selectedSystem: GameSystem?
    @State private var selectedTag: String?
    @State private var statusFilter: StatusFilter = .all
    @State private var showAddCard = false
    @State private var exportFile: ExportFile?
    @State private var exportError: String?
    @State private var isSelecting = false
    @State private var selection = Set<PersistentIdentifier>()

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
                || card.tags.contains { $0.lowercased().contains(q) }
            let matchesStatus: Bool
            switch statusFilter {
            case .all: matchesStatus = true
            case .inStock: matchesStatus = !card.isSold
            case .sold: matchesStatus = card.isSold
            }
            let matchesTag = selectedTag == nil || card.tags.contains(selectedTag!)
            return matchesSystem && matchesSearch && matchesStatus && matchesTag
        }
    }

    /// All distinct tags in the inventory, for the tag filter bar.
    private var allTags: [String] {
        Array(Set(cards.flatMap(\.tags))).sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
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
                    // Filters are a FIXED header (outside the scroll view) so their taps
                    // can't be swallowed by the scrolling card grid; only the grid scrolls.
                    VStack(spacing: Theme.spacing2) {
                        Picker("Status", selection: $statusFilter) {
                            ForEach(StatusFilter.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                        }
                        .pickerStyle(.segmented)
                        .padding(.horizontal, Theme.spacing4)
                        .padding(.top, Theme.spacing2)
                        systemFilterBar
                        if !allTags.isEmpty { tagFilterBar }
                        if filtered.isEmpty {
                            EmptyStateView(icon: "magnifyingglass", title: "No matches",
                                           message: "Nothing matches your search or filter.")
                                .padding(.top, Theme.spacing6)
                            Spacer()
                        } else {
                            ScrollView {
                                LazyVGrid(columns: columns, spacing: Theme.spacing3) {
                                    ForEach(filtered) { card in
                                        if isSelecting {
                                            Button { toggle(card) } label: {
                                                CardTile(card: card).environment(settings)
                                                    .overlay(alignment: .topLeading) { selectionMark(card) }
                                            }
                                            .buttonStyle(.plain)
                                        } else {
                                            NavigationLink {
                                                CardDetailView(card: card)
                                            } label: {
                                                CardTile(card: card).environment(settings)
                                            }
                                            .buttonStyle(.plain)
                                        }
                                    }
                                }
                                .padding(.horizontal, Theme.spacing4)
                                .padding(.bottom, Theme.spacing6)
                            }
                        }
                    }
                }
            }
            .background(Theme.background)
            .navigationTitle(isSelecting ? "\(selection.count) selected" : "Inventory")
            .navigationBarTitleDisplayMode(isSelecting ? .inline : .large)
            .searchable(text: $searchText, prompt: "Search name or short code")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if isSelecting {
                        Button(selection.count == filtered.count ? "Clear" : "Select all") { selectAllToggle() }
                    } else {
                        Menu {
                            Button {
                                isSelecting = true; selection = []
                            } label: { Label("Choose cards to export…", systemImage: "checkmark.circle") }
                            Section("Spreadsheet (CSV)") {
                                Button { exportCSV(cards) } label: { Label("All cards (\(cards.count))", systemImage: "tablecells") }
                                if filtered.count != cards.count {
                                    Button { exportCSV(filtered) } label: { Label("Shown (\(filtered.count))", systemImage: "line.3.horizontal.decrease") }
                                }
                            }
                            Section("QR codes for printing (PDF, 12/page)") {
                                Button { exportQRSheet(cards) } label: { Label("All cards (\(cards.count))", systemImage: "qrcode") }
                                if filtered.count != cards.count {
                                    Button { exportQRSheet(filtered) } label: { Label("Shown (\(filtered.count))", systemImage: "qrcode") }
                                }
                            }
                        } label: {
                            Image(systemName: "square.and.arrow.up")
                        }
                        .disabled(cards.isEmpty)
                        .accessibilityLabel("Export inventory")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if isSelecting {
                        Button("Done") { isSelecting = false; selection = [] }
                    } else {
                        Button { showAddCard = true } label: { Image(systemName: "plus") }
                            .accessibilityLabel("Add card")
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                if isSelecting { selectionBar }
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

    private func exportCSV(_ rows: [Card]) {
        guard !rows.isEmpty else { return }
        do { exportFile = ExportFile(url: try CSVExporter.writeTempFile(for: rows, currencyCode: settings.currencyCode)) }
        catch { exportError = error.localizedDescription }
    }

    private func exportQRSheet(_ rows: [Card]) {
        guard !rows.isEmpty else { return }
        do { exportFile = ExportFile(url: try QRSheetExporter.makePDF(for: rows)) }
        catch { exportError = error.localizedDescription }
    }

    // MARK: Selection

    private var selectedCards: [Card] { filtered.filter { selection.contains($0.persistentModelID) } }

    private func toggle(_ card: Card) {
        let id = card.persistentModelID
        if selection.contains(id) { selection.remove(id) } else { selection.insert(id) }
    }

    private func selectAllToggle() {
        if selection.count == filtered.count { selection = [] }
        else { selection = Set(filtered.map(\.persistentModelID)) }
    }

    private func selectionMark(_ card: Card) -> some View {
        let on = selection.contains(card.persistentModelID)
        return Image(systemName: on ? "checkmark.circle.fill" : "circle")
            .font(.title3)
            .foregroundStyle(on ? Theme.accent : .white, on ? .white : .black.opacity(0.35))
            .padding(8)
    }

    private var selectionBar: some View {
        HStack(spacing: Theme.spacing3) {
            Button { exportQRSheet(selectedCards) } label: {
                Label("QR sheet", systemImage: "qrcode").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            Button { exportCSV(selectedCards) } label: {
                Label("CSV", systemImage: "tablecells").frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
        }
        .disabled(selection.isEmpty)
        .padding(Theme.spacing3)
        .background(.bar)
    }

    private var systemFilterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Theme.spacing2) {
                chip("All", selected: selectedSystem == nil, tint: Theme.accent) { selectedSystem = nil }
                ForEach(systems) { system in
                    if system.cards?.isEmpty == false {
                        chip(system.code,
                             selected: selectedSystem?.persistentModelID == system.persistentModelID,
                             tint: Theme.accent) { selectedSystem = system }
                    }
                }
            }
            .padding(.horizontal, Theme.spacing4)
            .padding(.vertical, Theme.spacing2)
        }
    }

    private var tagFilterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Theme.spacing2) {
                chip("All tags", selected: selectedTag == nil, tint: Theme.accentSoft) { selectedTag = nil }
                ForEach(allTags, id: \.self) { tag in
                    chip(tag, selected: selectedTag == tag, tint: Theme.accentSoft) { selectedTag = tag }
                }
            }
            .padding(.horizontal, Theme.spacing4)
            .padding(.bottom, Theme.spacing2)
        }
    }

    /// A filter pill. Uses a tap gesture with an explicit hit shape — Buttons inside a
    /// horizontal ScrollView nested in the vertical grid ScrollView can mis-route taps to
    /// the cards below; this doesn't.
    private func chip(_ title: String, selected: Bool, tint: Color, action: @escaping () -> Void) -> some View {
        Text(title)
            .font(.subheadline.weight(.semibold))
            .padding(.horizontal, 14).padding(.vertical, 8)
            .background(selected ? tint : Theme.surface, in: Capsule())
            .foregroundStyle(selected ? .white : Theme.textPrimary)
            .contentShape(Capsule())
            .onTapGesture { withAnimation(.snappy, action) }
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
