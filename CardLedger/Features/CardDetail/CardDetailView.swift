import SwiftUI
import SwiftData

struct CardDetailView: View {
    @Environment(\.modelContext) private var context
    @Environment(SettingsStore.self) private var settings
    @Environment(\.dismiss) private var dismiss

    @Bindable var card: Card

    @State private var profitPercent: Double
    @State private var customMode = false
    @State private var showQR = false
    @State private var confirmDelete = false
    @State private var showEdit = false

    private let presets: [Double] = [10, 15, 20, 25]

    init(card: Card) {
        self.card = card
        // Seed the calculator from the card's game/app default the first time.
        _profitPercent = State(initialValue: 10)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.spacing4) {
                photoCarousel
                headerCard
                pricingCard
                qrCard
                actionsCard
            }
            .padding(Theme.spacing4)
        }
        .background(Theme.background)
        .navigationTitle(card.shortCode)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { profitPercent = settings.defaultProfitPercent }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showEdit = true } label: { Image(systemName: "pencil") }
                    .accessibilityLabel("Edit card")
            }
        }
        .alert("Delete this card?", isPresented: $confirmDelete) {
            Button("Delete", role: .destructive) { delete() }
            Button("Cancel", role: .cancel) {}
        } message: { Text("This removes the card and its photos from your inventory and iCloud.") }
        .sheet(isPresented: $showQR) { qrSheet }
        .sheet(isPresented: $showEdit) {
            AddCardView(editing: card).environment(settings)
        }
    }

    // MARK: Photos

    private var photoCarousel: some View {
        Group {
            let photos = card.sortedPhotos
            if photos.isEmpty {
                ZStack {
                    RoundedRectangle(cornerRadius: Theme.radiusLarge).fill(Theme.surfaceRaised)
                    Image(systemName: card.gameSystem?.iconSymbol ?? "rectangle.stack")
                        .font(.system(size: 60)).foregroundStyle(Theme.accent.opacity(0.4))
                }
                .frame(height: 280)
            } else {
                TabView {
                    ForEach(photos) { photo in
                        if let ui = UIImage(data: photo.imageData) {
                            Image(uiImage: ui).resizable().scaledToFit()
                        }
                    }
                }
                .frame(height: 320)
                .tabViewStyle(.page)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.radiusLarge))
            }
        }
    }

    // MARK: Header

    private var headerCard: some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: Theme.spacing2) {
                Text(card.name.isEmpty ? "Untitled card" : card.name).font(.title2.bold())
                HStack(spacing: Theme.spacing2) {
                    if let system = card.gameSystem {
                        StatChip(icon: system.iconSymbol, title: system.name)
                    }
                    StatChip(title: card.condition.label, tint: Theme.gold)
                    if card.quantity > 1 { StatChip(title: "×\(card.quantity)", tint: Theme.accentSoft) }
                }
                if !card.setName.isEmpty || !card.cardNumber.isEmpty || !card.rarity.isEmpty {
                    Text([card.setName, card.cardNumber, card.rarity].filter { !$0.isEmpty }.joined(separator: " · "))
                        .font(.subheadline).foregroundStyle(Theme.textSecondary)
                }
                if !card.tags.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: Theme.spacing2) {
                            ForEach(card.tags, id: \.self) { StatChip(icon: "tag", title: $0, tint: Theme.accentSoft) }
                        }
                    }
                }
                Divider()
                LabeledValue(label: "Paid", value: settings.money(card.purchasePrice), valueColor: Theme.gold)
                LabeledValue(label: "Purchased", value: card.purchaseDate.formatted(date: .abbreviated, time: .omitted))
                if !card.notes.isEmpty {
                    LabeledValue(label: "Notes", value: card.notes)
                }
            }
        }
    }

    // MARK: Pricing

    private var pricing: PricingResult {
        PricingEngine.compute(PricingInput(
            cost: card.purchasePrice,
            profitMargin: Decimal(profitPercent) / 100,
            vatRate: settings.vatRate,
            method: settings.taxMethod
        ))
    }

    private var pricingCard: some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: Theme.spacing3) {
                Label("Sale calculator", systemImage: "function").font(.headline)

                Picker("Profit", selection: $profitPercent) {
                    ForEach(presets, id: \.self) { Text("\(Int($0))%").tag($0) }
                }
                .pickerStyle(.segmented)

                VStack(spacing: 6) {
                    HStack {
                        Text("Target profit").foregroundStyle(Theme.textSecondary)
                        Spacer()
                        Text("\(Int(profitPercent))%").fontWeight(.semibold)
                    }
                    Slider(value: $profitPercent, in: 0...100, step: 1)
                }
                .font(.subheadline)

                Divider()

                // The headline number.
                HStack(alignment: .firstTextBaseline) {
                    Text("List at").font(.subheadline).foregroundStyle(Theme.textSecondary)
                    Spacer()
                    Text(settings.money(pricing.salePrice)).font(.system(.largeTitle, design: .rounded).bold())
                        .foregroundStyle(Theme.accent)
                }

                LabeledValue(label: "Includes VAT (\(Int(settings.vatPercent))%)", value: settings.money(pricing.vatAmount))
                LabeledValue(label: "You keep (after VAT)", value: settings.money(pricing.netReceived))
                LabeledValue(label: "Profit", value: settings.money(pricing.grossProfit),
                             valueColor: pricing.grossProfit >= 0 ? Theme.profit : Theme.loss)
                Text(settings.taxMethod.label)
                    .font(.caption).foregroundStyle(Theme.textSecondary)
            }
        }
    }

    // MARK: QR

    private var qrCard: some View {
        SurfaceCard {
            HStack(spacing: Theme.spacing4) {
                if let qr = QRCodeGenerator.image(for: card.shortCode) {
                    qr.resizable().interpolation(.none).frame(width: 90, height: 90)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("Short code").font(.caption).foregroundStyle(Theme.textSecondary)
                    Text(card.shortCode).font(.title3.monospaced().bold())
                    Button { showQR = true } label: {
                        Label("Show large QR", systemImage: "qrcode")
                    }.font(.subheadline)
                }
                Spacer()
            }
        }
    }

    private var qrSheet: some View {
        VStack(spacing: Theme.spacing4) {
            Text(card.name).font(.headline)
            if let qr = QRCodeGenerator.image(for: card.shortCode) {
                qr.resizable().interpolation(.none).scaledToFit().padding(Theme.spacing6)
            }
            Text(card.shortCode).font(.title.monospaced().bold())
            Text("Scan in CardLedger to open this card").font(.footnote).foregroundStyle(Theme.textSecondary)
        }
        .padding()
        .presentationDetents([.medium, .large])
    }

    // MARK: Actions

    private var actionsCard: some View {
        VStack(spacing: Theme.spacing2) {
            if card.isSold {
                SurfaceCard {
                    LabeledValue(label: "Sold for", value: settings.money(card.salePrice), valueColor: Theme.profit)
                }
                Button("Mark as unsold") { card.isSold = false; save() }
                    .buttonStyle(.bordered)
            } else {
                Button {
                    card.isSold = true
                    card.salePrice = pricing.salePrice
                    card.soldDate = Date()
                    save()
                } label: { Label("Mark as sold at \(settings.money(pricing.salePrice))", systemImage: "checkmark.seal.fill") }
                    .buttonStyle(PrimaryButtonStyle())
            }

            Button(role: .destructive) { confirmDelete = true } label: {
                Label("Delete card", systemImage: "trash")
            }
            .buttonStyle(.bordered)
            .tint(Theme.loss)
        }
    }

    private func save() { try? context.save() }

    private func delete() {
        context.delete(card)
        try? context.save()
        dismiss()
    }
}
