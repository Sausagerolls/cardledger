import SwiftUI
import SwiftData
import PhotosUI

struct AddCardView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(SettingsStore.self) private var settings

    @Query(sort: \GameSystem.sortIndex) private var systems: [GameSystem]

    /// When set, the form edits this card instead of creating a new one.
    var editing: Card?

    @State private var didLoad = false

    // Form state
    @State private var name = ""
    @State private var setName = ""
    @State private var cardNumber = ""
    @State private var rarity = ""
    @State private var condition: CardCondition = .nearMint
    @State private var priceText = ""
    @State private var quantity = 1
    @State private var purchaseDate = Date()
    @State private var notes = ""
    @State private var tags: [String] = []
    @State private var tagInput = ""
    @State private var selectedSystem: GameSystem?
    @State private var externalImageURL = ""

    // Photos
    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var images: [UIImage] = []
    @State private var showCamera = false

    // Auto-fill
    @State private var showLookup = false

    var body: some View {
        NavigationStack {
            Form {
                photoSection
                gameSection
                detailsSection
                priceSection
                tagsSection
                notesSection
            }
            .navigationTitle(editing == nil ? "New Card" : "Edit Card")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }.fontWeight(.semibold)
                        .disabled(!canSave)
                }
            }
            .onAppear(perform: loadIfNeeded)
            .sheet(isPresented: $showLookup) {
                CardLookupView(gameCode: selectedSystem?.code ?? "") { result in
                    apply(result)
                }
                .environment(settings)
            }
            .fullScreenCover(isPresented: $showCamera) {
                CameraPicker { image in images.append(image) }
                    .ignoresSafeArea()
            }
        }
    }

    // MARK: Sections

    private var photoSection: some View {
        Section("Photos") {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Theme.spacing2) {
                    if CameraPicker.isAvailable {
                        photoTile(icon: "camera.fill", label: "Take") { showCamera = true }
                    }
                    PhotosPicker(selection: $pickerItems, maxSelectionCount: 8, matching: .images) {
                        photoTileLabel(icon: "photo.on.rectangle", label: "Library")
                    }
                    ForEach(Array(images.enumerated()), id: \.offset) { index, img in
                        Image(uiImage: img).resizable().scaledToFill()
                            .frame(width: 84, height: 110)
                            .clipShape(RoundedRectangle(cornerRadius: Theme.radiusSmall))
                            .overlay(alignment: .topTrailing) {
                                Button { images.remove(at: index) } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundStyle(.white, .black.opacity(0.5))
                                }
                                .padding(4)
                            }
                    }
                }
                .padding(.vertical, 4)
            }
            .onChange(of: pickerItems) { _, items in Task { await loadImages(items) } }
        }
    }

    private func photoTile(icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { photoTileLabel(icon: icon, label: label) }.buttonStyle(.plain)
    }

    private func photoTileLabel(icon: String, label: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon).font(.title2)
            Text(label).font(.caption)
        }
        .frame(width: 84, height: 110)
        .background(Theme.surfaceRaised, in: RoundedRectangle(cornerRadius: Theme.radiusSmall))
        .foregroundStyle(Theme.accent)
    }

    private var gameSection: some View {
        Section("Game system") {
            Picker("System", selection: $selectedSystem) {
                ForEach(systems) { system in
                    Text(system.name).tag(Optional(system))
                }
            }
            Button {
                showLookup = true
            } label: {
                Label("Auto-fill from card database", systemImage: "sparkle.magnifyingglass")
            }
            .disabled(selectedSystem == nil)
        }
    }

    private var detailsSection: some View {
        Section("Card details") {
            TextField("Name", text: $name)
            TextField("Set", text: $setName)
            TextField("Card number", text: $cardNumber)
            TextField("Rarity", text: $rarity)
            Picker("Condition", selection: $condition) {
                ForEach(CardCondition.allCases) { Text($0.label).tag($0) }
            }
        }
    }

    private var priceSection: some View {
        Section {
            HStack {
                Text(settings.currencyCode)
                TextField("Price paid", text: $priceText).keyboardType(.decimalPad)
            }
            DatePicker("Date", selection: $purchaseDate, displayedComponents: .date)
            if editing == nil {
                Stepper("Copies to add: \(quantity)", value: $quantity, in: 1...99)
            }
        } header: {
            Text("Purchase")
        } footer: {
            if editing == nil && quantity > 1 {
                Text("Each copy is logged separately with its own unique code and QR, so you can track and sell them individually.")
            }
        }
    }

    private var tagsSection: some View {
        Section {
            if !tags.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: Theme.spacing2) {
                        ForEach(tags, id: \.self) { tag in
                            Button { tags.removeAll { $0 == tag } } label: {
                                HStack(spacing: 4) {
                                    Text(tag)
                                    Image(systemName: "xmark.circle.fill")
                                }
                                .font(.footnote.weight(.semibold))
                                .padding(.horizontal, 10).padding(.vertical, 6)
                                .background(Theme.accent.opacity(0.14), in: Capsule())
                                .foregroundStyle(Theme.accent)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
            HStack {
                TextField("Add a tag (e.g. Japanese, Graded)", text: $tagInput)
                    .autocorrectionDisabled()
                    .onSubmit(addTag)
                Button("Add", action: addTag)
                    .disabled(tagInput.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        } header: {
            Text("Tags")
        } footer: {
            Text("Use tags for things like language, grading or anything you want to filter by later.")
        }
    }

    private func addTag() {
        let t = tagInput.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty, !tags.contains(where: { $0.caseInsensitiveCompare(t) == .orderedSame }) else {
            tagInput = ""; return
        }
        tags.append(t)
        tagInput = ""
    }

    private var notesSection: some View {
        Section("Notes") {
            TextField("Optional notes", text: $notes, axis: .vertical).lineLimit(2...5)
        }
    }

    // MARK: Logic

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty && selectedSystem != nil
    }

    /// Populate the form once: from the edited card, or defaults for a new card.
    private func loadIfNeeded() {
        guard !didLoad else { return }
        didLoad = true
        guard let card = editing else {
            if selectedSystem == nil { selectedSystem = systems.first }
            return
        }
        name = card.name
        setName = card.setName
        cardNumber = card.cardNumber
        rarity = card.rarity
        condition = card.condition
        priceText = card.purchasePriceMinor == 0 ? "" : String(format: "%.2f", NSDecimalNumber(decimal: card.purchasePrice).doubleValue)
        quantity = max(card.quantity, 1)
        purchaseDate = card.purchaseDate
        notes = card.notes
        tags = card.tags
        selectedSystem = card.gameSystem ?? systems.first
        externalImageURL = card.externalImageURL
        images = card.sortedPhotos.compactMap { UIImage(data: $0.imageData) }
    }

    private func loadImages(_ items: [PhotosPickerItem]) async {
        var loaded: [UIImage] = []
        for item in items {
            if let data = try? await item.loadTransferable(type: Data.self), let ui = UIImage(data: data) {
                loaded.append(ui)
            }
        }
        images.append(contentsOf: loaded)   // accumulate with any camera shots
        pickerItems = []                     // reset so the same pick can be added again
    }

    private func apply(_ result: CardLookupResult) {
        if !result.name.isEmpty { name = result.name }
        if !result.setName.isEmpty { setName = result.setName }
        if !result.number.isEmpty { cardNumber = result.number }
        if !result.rarity.isEmpty { rarity = result.rarity }
        externalImageURL = result.imageURL
    }

    private func save() {
        addTag()   // include any tag typed but not yet added
        guard let system = selectedSystem else { return }
        let priceMinor = Self.minorUnits(from: priceText)
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        let datas = images.compactMap { $0.jpegData(compressionQuality: 0.8) }

        if let editing {
            // Editing a single instance — keep its unique code stable.
            write(to: editing, system: system, priceMinor: priceMinor, name: trimmedName)
            for old in editing.photos ?? [] { context.delete(old) }
            editing.photos = []
            attach(datas, to: editing)
            try? context.save()
            dismiss()
            return
        }

        // Create one record per physical copy, each with its own unique code + QR,
        // so multiples of the same card can be tracked and sold individually.
        let copies = max(quantity, 1)
        var usedCodes = Set<String>()
        for _ in 0..<copies {
            var code = ShortCodeGenerator.makeUnique(prefix: system.code, in: context)
            while usedCodes.contains(code) { code = ShortCodeGenerator.make(prefix: system.code) }
            usedCodes.insert(code)

            let card = Card(shortCode: code, name: trimmedName, gameSystem: system,
                            purchasePriceMinor: priceMinor, purchaseDate: purchaseDate, quantity: 1)
            write(to: card, system: system, priceMinor: priceMinor, name: trimmedName)
            context.insert(card)
            attach(datas, to: card)
        }
        try? context.save()
        dismiss()
    }

    /// Write the scalar fields onto a card (an instance is always quantity 1).
    private func write(to card: Card, system: GameSystem, priceMinor: Int, name: String) {
        card.name = name
        card.gameSystem = system
        card.purchasePriceMinor = priceMinor
        card.purchaseDate = purchaseDate
        card.quantity = 1
        card.setName = setName
        card.cardNumber = cardNumber
        card.rarity = rarity
        card.condition = condition
        card.notes = notes
        card.tags = tags
        card.externalImageURL = externalImageURL
    }

    private func attach(_ datas: [Data], to card: Card) {
        for (index, data) in datas.enumerated() {
            let photo = CardPhoto(imageData: data, sortIndex: index)
            photo.card = card
            context.insert(photo)
        }
    }

    /// Parse user-entered price ("12.50") into integer minor units (1250).
    static func minorUnits(from text: String) -> Int {
        let normalized = text.replacingOccurrences(of: ",", with: ".")
        let value = Decimal(string: normalized) ?? 0
        return NSDecimalNumber(decimal: value * 100).intValue
    }
}
